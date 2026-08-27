extends Node2D
class_name Station

## Generic production station: holds at most one Part at a time (batching
## beyond that isn't modeled yet), runs it out, then hands it to
## next_station. Data-driven so one scene covers every station in the shop
## (see GameData). Once staffed by a Technician, it creates/routes parts on
## its own - see assign_technician() and _process().
##
## All player interaction (Queue, Collect, batch size, hiring, inserting a
## held Part, upgrading) now happens through StationDetailMenu, opened by
## tapping the station on the floor (main.gd hit-tests get_click_rect()). The
## floor itself is display-only: sprite, name, status, timer bar. The public
## methods below are that popup's whole surface for driving a Station.
##
## station_id, is_pipeline_entry, and next_station are wired externally by
## main.gd after every Station in GameData.PIPELINE_ORDER has been spawned.

enum StationType { QUEUE, BATCHED, AUTOMATIC }
enum State { IDLE, RUNNING, READY }

## Design doc Section 21.4/Section 4: Shelling's Tier 2+ behavior - "parallel
## independent timers" - is a genuinely different runtime model than every
## other station's one-Part/one-Timer-node setup, not just a bigger batch_cap.
## Each ShellingRun ticks its own elapsed time independently in
## _process_parallel_shelling() below, rather than sharing the single
## station_timer node the rest of this class uses. Only ever used when
## is_parallel_shelling() is true (station_id=="shelling" and
## current_tier>=2); Tier 1 Shelling still runs through the normal
## current_part/station_timer path unchanged.
class ShellingRun:
	var part: Part
	var elapsed: float = 0.0
	var duration: float

	func _init(p_part: Part, p_duration: float) -> void:
		part = p_part
		duration = max(p_duration, 0.01)

	var time_left: float:
		get: return max(duration - elapsed, 0.0)
	var is_done: bool:
		get: return elapsed >= duration

## Fallback local-space bounds for the name/status/timer stack below the
## sprite, unioned into get_click_rect() below. On its own this would badly
## undershoot for Burnout/Pour, whose shared full-size art (1254x1254) renders
## far bigger than Printing's (360x460) at the same 0.18 sprite scale.
const LABEL_STACK_RECT: Rect2 = Rect2(-20.0, 0.0, 150.0, 150.0)

## GameData.StationDef.id - lets StationDetailMenu match held Parts destined
## for this specific station without guessing from station_name.
var station_id: String = ""

## Every tier's sprite renders at this scale before any zoom compensation
## (see set_sprite_scale_multiplier()) - was previously hardcoded directly
## on the StationSprite node in station.tscn.
const BASE_SPRITE_SCALE: float = 0.18

@export var station_name: String = "Station"
@export var station_type: StationType = StationType.QUEUE

@export_range(1, 5, 1) var current_tier: int = 1:
	set(value):
		current_tier = clampi(value, 1, 5)
		if is_inside_tree():
			_update_sprite()

## Prototype-scale seconds (see GameData.PROTOTYPE_SECONDS_PER_MINUTE), not real minutes.
@export var timer_duration: float = 5.0
## -1 means unlimited (used by Ship, which has no batch cap).
## How many parts run together sharing one timer. Design doc Section 21.1:
## no longer derives rack space from this - rack_capacity below is a fully
## independent stat. batch_cap itself is still mostly a flat Tier 1 number
## except where a station's current_tier is documented to change it
## station-specifically (see _apply_tier_batch_effects() below) - printer
## instances and Abrasive Blast unlock more batching at higher tiers per
## Section 4's revised table; Shelling replaces batching with a different
## runtime model entirely at Tier 2+ (see shelling_active_parts below).
## General "every BATCHED station gets a bigger batch_cap at higher tiers"
## isn't implemented - Section 21.8 only calls out those three cases.
@export var batch_cap: int = 1
## How many parts can physically wait at this station (in the rack, not the
## active slot), completely independent of batch_cap now (design doc Section
## 21.1 - the old batch_cap-derived _rack_capacity() is gone). Every station
## starts at 1 - a small desk-like holding spot - and grows via its own
## purchase, try_upgrade_rack() below. Capped at RACK_SLOT_COUNT worth of
## slots (10) since that's a hard UI limit - see StationDetailMenu's fixed
## 10-button rack grid.
@export var rack_capacity: int = 1
const MAX_RACK_CAPACITY: int = 10
## One texture per tier, index 0 = Tier 1 ... index 4 = Tier 5.
## Leave empty (or entries null) for stations without art yet; a placeholder is used instead.
@export var tier_sprites: Array[Texture2D] = []
## Per-station fudge factor on top of BASE_SPRITE_SCALE, for a real photo
## asset whose native resolution doesn't match the ~360-460px most station
## art assumes (bug fix, design feedback: "the cleaner is a bit larger than
## the rest" - cleaner_1/2/3.png are 1254x1254, the same resolution class as
## Burnout/Pour's real art, but Clean sits packed into a tight row of small
## Print Room stations rather than having a whole room mostly to itself like
## Burnout/Pour do). 1.0 (no change) for every station except Clean.
@export var sprite_scale_override: float = 1.0
## Real per-state art (Clean is the first station to get this - see
## cleaner_1/2/3.png) - index 0 = idle, 1 = running, 2 = ready. Distinct from
## tier_sprites above, which is indexed by current_tier: a station can only
## ever have ONE of these two art systems active at a time (state_sprites
## wins if both are somehow populated - see _update_sprite()), since tier
## and state are two different axes a single static photo can't represent
## at once. Leave empty for a station without real per-state art; falls back
## to tier_sprites, then the generic tinted placeholder, same as before.
@export var state_sprites: Array[Texture2D] = []

## True only for the first station in GameData.PIPELINE_ORDER (Printing) -
## the only place a brand new Part gets created rather than received.
## Exported (default true) so station.tscn's own standalone preview instance
## behaves like Printing when run directly; main.gd overrides this for all
## 11 real instances based on their actual position in the pipeline.
@export var is_pipeline_entry: bool = true
## Where a finished Part goes next; null for Ship, the last station.
var next_station: Station = null

var current_state: State = State.IDLE
var batch_size: int = 1
var current_part: Part = null
## Parts waiting their turn once current_part is running - design doc
## Section 7's "station queue rack". This is buffering slack, NOT the real
## simultaneous multi-part batching from Section 4/17 (still not built):
## rack parts still process one at a time through current_part, sequentially,
## they just don't have to wait for an upstream station to hold onto them.
var queue_rack: Array[Part] = []
## Design request, this session: multiple technicians can now be assigned to
## the same station at once (previously a station only ever had one, which
## replaced whoever was there before). See active_worker below for who
## actually runs the station's automation at any given moment - being
## assigned here doesn't by itself mean "working here."
var assigned_technicians: Array[Technician] = []
## Whichever ONE assigned technician is currently physically present AND
## actually running this station's automation right now - "there shouldn't
## be more than one technician working a station." Claimed by whoever
## arrives first while nobody else holds it (see _technician_act()), cleared
## the moment that technician leaves (_travel_if_worthwhile()) or gets
## unassigned. Anyone else assigned who's ALSO physically present (e.g.
## arrived carrying a part bound here after someone else already claimed the
## slot) is a mere visitor - see _technician_act_as_visitor() - they can
## still drop cargo into the rack, just don't compete to run the machine.
var active_worker: Technician = null
var _has_tiered_art: bool = false
var _has_state_art: bool = false

## How long the interaction-flourish animation holds each state_sprites frame
## before advancing to the next one (design request: "an animation that
## plays when a technician interacts with the station"). Three frames over
## Technician.INTERACT_SECONDS (1.5s) at 0.5s each lands exactly on the last
## frame right as the interaction ends, so the flourish always finishes
## cleanly rather than getting cut off mid-cycle.
const INTERACT_ANIM_FRAME_SECONDS: float = 0.5
var _interact_anim_elapsed: float = 0.0

## Parallel-shelling-only state (design doc Section 21.4) - see
## is_parallel_shelling(). shelling_active_parts holds one ShellingRun per
## Part currently mid-cycle, up to batch_cap of them running at once, each on
## its own independent clock. shelling_ready_parts holds Parts whose run
## finished but haven't been sent/collected onward yet - the parallel
## equivalent of a single READY current_part, except there can be several at
## once here. Both empty, always, for every station except Shelling at
## current_tier >= 2.
var shelling_active_parts: Array[ShellingRun] = []
var shelling_ready_parts: Array[Part] = []


## Whether this Station is currently running Shelling's Tier 2+ parallel
## model rather than the normal single current_part/station_timer model -
## design doc Section 4: "Shelling: single part at Tier 1; parallel
## independent timers at Tier 2+." Checked before almost every state-mutating
## method below so the exact same Station scene/script serves both models
## without duplicating the whole class.
func is_parallel_shelling() -> bool:
	return station_id == "shelling" and current_tier >= 2

## Design doc Section 9, "Push Through" - Pour only. Armed by
## StationDetailMenu's Push Through checkbox (only shown for the Pour
## station); consumed the moment the NEXT part actually starts running here
## (_start_running() stamps it onto that part and disarms this, a one-shot
## per-part choice rather than a sticky mode) - see Part.is_push_through and
## _resolve_push_through() below.
var push_through_armed: bool = false

@onready var station_sprite: Sprite2D = $StationSprite
@onready var name_label: Label = $NameLabel
@onready var status_label: Label = $StatusLabel
@onready var timer_bar: ProgressBar = $TimerBar
@onready var timer_bar_label: Label = $TimerBar/TimerBarLabel
@onready var station_timer: Timer = $StationTimer


func _ready() -> void:
	batch_size = batch_cap
	station_timer.one_shot = true
	station_timer.timeout.connect(_on_station_timer_timeout)

	name_label.text = station_name

	station_sprite.scale = Vector2.ONE * BASE_SPRITE_SCALE * sprite_scale_override

	timer_bar.min_value = 0.0
	timer_bar.max_value = max(timer_duration, 0.01)

	_update_sprite()
	_update_display()


## Called by main.gd whenever camera zoom changes. multiplier is applied on
## top of BASE_SPRITE_SCALE, letting the floor shrink sprites a bit extra at
## high magnification (low zoom) so stations don't feel oversized zoomed all
## the way in. get_click_rect() reads station_sprite.scale live, so the
## clickable area shrinks right along with the visible sprite.
func set_sprite_scale_multiplier(multiplier: float) -> void:
	station_sprite.scale = Vector2.ONE * BASE_SPRITE_SCALE * multiplier * sprite_scale_override


func _process(delta: float) -> void:
	if is_parallel_shelling():
		_process_parallel_shelling(delta)
	elif current_state == State.RUNNING:
		timer_bar.value = station_timer.time_left
		timer_bar_label.text = "%.1fs" % station_timer.time_left

	if _has_state_art:
		if _is_interact_animating():
			_interact_anim_elapsed += delta
		else:
			_interact_anim_elapsed = 0.0
		_apply_state_sprite()

	# Design request, this session: several technicians can be assigned here
	# at once now - iterate a duplicate defensively (an unassign triggered
	# mid-loop, while unlikely, would otherwise mutate assigned_technicians
	# out from under this for-loop).
	for tech: Technician in assigned_technicians.duplicate():
		if tech.current_station_id == station_id:
			_technician_act(tech)


## Ticks every in-progress ShellingRun independently (design doc Section
## 21.4) - each Part finishes on its own schedule rather than all together.
## Iterates a duplicate since _finish_shelling_run() below mutates
## shelling_active_parts (the real array) while this loop is still running.
func _process_parallel_shelling(delta: float) -> void:
	for run in shelling_active_parts.duplicate():
		run.elapsed += delta
		if run.is_done:
			_finish_shelling_run(run)

	if shelling_active_parts.is_empty():
		_clear_timer_bar()
	else:
		var soonest: ShellingRun = shelling_active_parts[0]
		for run in shelling_active_parts:
			if run.time_left < soonest.time_left:
				soonest = run
		timer_bar.max_value = max(soonest.duration, 0.01)
		timer_bar.value = soonest.time_left
		timer_bar_label.text = "%.1fs" % soonest.time_left


func _start_shelling_run(part: Part) -> void:
	# Push Through (design doc Section 21.6, generalized beyond Pour) - same
	# one-shot arm/consume pattern as _start_running() above, just against
	# whichever Part starts the next parallel run instead of the single
	# current_part.
	if push_through_armed:
		part.is_push_through = true
		push_through_armed = false
	shelling_active_parts.append(ShellingRun.new(part, _effective_timer_duration()))
	_update_parallel_state()
	_update_display()


func _finish_shelling_run(run: ShellingRun) -> void:
	shelling_active_parts.erase(run)
	if run.part.is_push_through:
		_resolve_push_through(run.part)
		return
	var part := run.part
	part.status = Part.Status.READY_TO_ROUTE
	_maybe_flag_defect(part)
	shelling_ready_parts.append(part)
	_update_parallel_state()
	_update_display()


## Keeps current_state a reasonable aggregate for parallel shelling, so every
## generic reader of current_state (get_overview_status() callers, the
## Station Detail Menu, Technician._priority_tier_for()'s READY/IDLE checks)
## still sees something sensible: READY takes priority (there's something to
## collect/route), then RUNNING (at least one run in progress), else IDLE.
func _update_parallel_state() -> void:
	if not shelling_ready_parts.is_empty():
		current_state = State.READY
	elif not shelling_active_parts.is_empty():
		current_state = State.RUNNING
	else:
		current_state = State.IDLE


## One-time migration for a Shelling station that was already running a Part
## the normal single-current_part way (Tier 1) at the moment it crossed into
## Tier 2 - without this, that in-progress run would keep ticking under the
## old station_timer (whose timeout handler still fires and still works) while
## _process() stops reading it entirely once is_parallel_shelling() flips
## true, leaving current_part silently stuck instead of visibly wrong. Wraps
## whatever time was already spent into a ShellingRun with the same time_left
## the player was already looking at, then hands off to the parallel model.
func _migrate_to_parallel_shelling() -> void:
	if current_part == null:
		return
	var duration := timer_bar.max_value
	var time_left := station_timer.time_left
	station_timer.stop()
	var run := ShellingRun.new(current_part, duration)
	run.elapsed = max(duration - time_left, 0.0)
	current_part = null
	shelling_active_parts.append(run)
	_update_parallel_state()
	_update_display()


## Called every frame a technician is physically here (Technician.tick()
## keeps them "present" - i.e. tech.current_station_id == station_id, see
## _process()'s loop above - while they're on their post-action interact
## cooldown too, so this just re-checks and
## no-ops until that clears). Tries exactly ONE real interaction - deposit a
## carried part bound here, ship/hand off a ready part, or load the active
## slot from the rack/Awaiting Transfer/a new contract - and if it did
## something, gives the technician a brief real pause
## (Technician.begin_interacting()) before this fires again, representing
## physically handling it rather than instant teleportation. There's no
## fixed "stand around" timer: if there's truly nothing left to interact
## with here and this technician covers more than one station, they head
## straight to the next one in rotation (Technician.start_traveling_to()) -
## a solo-station technician just keeps re-checking here forever instead.
func _technician_act(tech: Technician) -> void:
	if tech.is_interacting:
		return

	# Design request, this session: "only the first one to get there will
	# stay at that station" - claiming happens purely by being the first
	# present technician to reach this point while nobody else holds the
	# slot, regardless of whether they end up finding anything to do.
	if active_worker == null:
		active_worker = tech

	if active_worker != tech:
		_technician_act_as_visitor(tech)
		return

	if _deposit_one_carried_part(tech):
		tech.begin_interacting()
		return

	if _has_ready_part_to_send() and _try_send_to_next_station(tech):
		tech.begin_interacting()
		return

	# Delivering cargo already picked up takes priority over starting brand
	# new local work - without this, a technician working a station that
	# always has more to do (an entry station with contracts queued, or a
	# rack that keeps refilling) would never actually leave to deliver a Part
	# sitting in carried_parts, since _fill_active_slot_if_possible() below
	# would just keep "succeeding" here forever. _deposit_one_carried_part()
	# above already handled anything bound HERE - this is specifically about
	# something bound elsewhere, which only pick_next_station() can route to.
	if not tech.carried_parts.is_empty() and tech.has_multiple_real_stations():
		_travel_if_worthwhile(tech)
		return

	# Not just _auto_queue_if_possible(): a station that's been idle and
	# staffed since before anything was ever held (so its slot never had a
	# "just freed up" moment to react to) still needs to notice a Part
	# sitting in Awaiting Transfer bound for it - see
	# _claim_held_parts_bound_here(). _fill_active_slot_if_possible() tries
	# that before falling through to auto-queue. _has_open_slot_to_fill()
	# rather than a plain "current_state == IDLE" check specifically so a
	# parallel-shelling station with SOME slots busy and one free still gets
	# noticed - current_state alone can't distinguish "fully busy" from
	# "partially busy with room for one more" once there's more than one slot.
	if _has_open_slot_to_fill() and _fill_active_slot_if_possible():
		tech.begin_interacting()
		return

	if tech.has_multiple_real_stations():
		_travel_if_worthwhile(tech)


## A technician physically here but NOT the active worker - someone else
## already claimed that role. Design request, this session: "there shouldn't
## be more than one technician working a station but they can transfer a
## part into the queue rack if they have one." Tries exactly one cargo
## deposit (the only thing a visitor can meaningfully do), then - whether
## that succeeded or there was nothing to deposit - immediately looks
## elsewhere rather than lingering with no ongoing role here. In practice
## this mostly only happens for a technician carrying cargo bound here (a
## non-cargo technician should already have excluded this station as a
## candidate once someone else claimed it - see
## Technician._priority_tier_for()) or for the rare loser of a same-tick race
## to claim an unclaimed station.
func _technician_act_as_visitor(tech: Technician) -> void:
	if _deposit_one_carried_part(tech):
		tech.begin_interacting()
		return
	if tech.has_multiple_real_stations():
		_travel_if_worthwhile(tech)


## Only actually sends tech walking if Technician.pick_next_station() found
## somewhere that genuinely has something to do - it now returns tech's own
## current_station_id (a "stay put" signal) when every other assigned
## station is equally unworthwhile, rather than always picking a "best of
## nothing" candidate. Calling Technician.start_traveling_to() with tech's
## own current station would be a real bug, not just a no-op: it
## unconditionally sets is_traveling=true and clears current_station_id to
## "", which would make presence checks go false for an instant even though
## they never actually left, and previously caused two technicians with
## nothing productive to do at either of their two stations to walk back and
## forth between them forever (reported as technicians "stuck bouncing back
## and forth between 2 stations") - each arrival found the exact same
## "nothing to do" verdict and immediately turned around again. Also
## releases active_worker if tech was holding it, so whoever's left present
## (if anyone) can claim it next.
func _travel_if_worthwhile(tech: Technician) -> void:
	var next_id := tech.pick_next_station(GameData.station_by_id)
	if next_id != tech.current_station_id:
		if active_worker == tech:
			active_worker = null
		tech.start_traveling_to(next_id)


## Whether there's a real reason for the assigned technician to come here
## right now - used by Technician.pick_next_station() (design doc Section
## 7's routing strategy) to decide where's actually worth walking to next,
## instead of guessing blindly. Mirrors the same checks _technician_act()
## itself would make on arrival, just evaluated remotely.
func has_actionable_work() -> bool:
	if _has_ready_part_to_send():
		return true
	if _has_open_slot_to_fill():
		if not queue_rack.is_empty():
			return true
		for part in GameData.held_parts:
			if GameData.next_station_id_for(part) == station_id:
				return true
		# Bug fix (this session): this used to say yes here purely because a
		# contract existed, without checking can_start_new_work() - so a
		# pipeline-entry station paused by the new backpressure gate (see
		# that method's comment) still claimed to have real work. A
		# technician chasing that false signal would arrive, find
		# _fill_active_slot_if_possible() correctly refuse to do anything,
		# and - since the backpressure state hadn't changed - still see this
		# same station as the "best" option again shortly after leaving,
		# producing exactly the same "stuck bouncing back and forth"
		# symptom the earlier NOTHING_TIER fix was meant to end, just with a
		# blocked entry station standing in for "nothing to do anywhere."
		if is_pipeline_entry and can_start_new_work() and not GameData.get_active_contracts().is_empty():
			return true
	return false


## Whether there's currently a finished Part here worth a technician carrying
## onward - current_part (normal model) or the front of shelling_ready_parts
## (parallel shelling, design doc Section 21.4, where more than one Part can
## be simultaneously done at once).
func _has_ready_part_to_send() -> bool:
	if is_parallel_shelling():
		return not shelling_ready_parts.is_empty()
	return current_state == State.READY and current_part != null

## Whether there's an empty slot a technician could load right now -
## current_part == null (normal model) or fewer running ShellingRuns than
## batch_cap (parallel shelling) - see _technician_act()'s own comment for
## why this can't just be "current_state == IDLE" once a station can be
## simultaneously part-busy and part-free.
func _has_open_slot_to_fill() -> bool:
	if is_parallel_shelling():
		return shelling_active_parts.size() < max(batch_cap, 1)
	return current_part == null


## Whether this station is currently being actively worked - i.e.
## active_worker is set. Public since it's needed outside this class (design
## doc-adjacent bug fix, this session): a station's manual Collect action
## used to be hidden entirely whenever a technician was assigned here at
## all, even if that technician was off working a different station of
## theirs and might not physically be back for a while. With only a handful
## of technicians now covering a much longer pipeline (Section 21 added
## Clean/Patching/Mold Prep), a Ready Part could sit stuck indefinitely with
## no way for the player to intervene - reported as "there's no way for
## parts to make it to ship." See collect_ready_part()'s own comment for the
## actual fix, and active_worker's own comment for what "actively worked"
## means now that several technicians can be assigned at once.
func is_technician_present() -> bool:
	return active_worker != null


## Extra slop added around the sprite+label bounds below so a tap doesn't
## have to land pixel-perfect - real clicks routinely miss a tight hit box
## by tens of pixels, and this is meant to be touch-friendly per the design doc.
const CLICK_PADDING: float = 24.0

## Local-space bounds main.gd hit-tests a floor tap against to open this
## station's detail menu: the sprite's actual current on-screen footprint
## (Sprite2D.get_rect() already accounts for its texture size and centered
## origin, scaled by the sprite's own scale) unioned with the label stack
## below it, then padded. Computed fresh each call since it depends on
## whatever texture is currently assigned, not a fixed guess - see the
## LABEL_STACK_RECT comment.
func get_click_rect() -> Rect2:
	var local_sprite_rect := station_sprite.get_rect()
	var sprite_rect := Rect2(
		station_sprite.position + local_sprite_rect.position * station_sprite.scale,
		local_sprite_rect.size * station_sprite.scale
	)
	return sprite_rect.merge(LABEL_STACK_RECT).grow(CLICK_PADDING)


## Whether this station can currently take an incoming Part. Ship never
## holds parts - it credits and discards them instantly - so it always has
## room. Otherwise: room if the active slot is free, or the queue rack has
## space (see rack_capacity).
func can_accept_part() -> bool:
	if station_type == StationType.AUTOMATIC:
		return true
	if _has_open_slot_to_fill():
		return true
	return queue_rack.size() < rack_capacity


## Called by the previous station in the pipeline (or StationDetailMenu,
## inserting a held Part directly) to hand off a finished Part. Starts
## running immediately if there's an open slot, otherwise waits in the queue
## rack until _fill_active_slot_if_possible() pulls it forward. Parallel
## shelling (design doc Section 21.4) can have more than one open slot at
## once - see _has_open_slot_to_fill()/_start_shelling_run().
func receive_part(part: Part) -> void:
	part.current_station_index += 1

	if station_type == StationType.AUTOMATIC:
		_ship_part(part)
		return

	part.status = Part.Status.IN_STATION

	if is_parallel_shelling():
		if _has_open_slot_to_fill():
			_start_shelling_run(part)
		else:
			queue_rack.append(part)
		_update_display()
		return

	if current_part == null:
		current_part = part
		_start_running()
	else:
		queue_rack.append(part)

	_update_display()


func _ship_part(part: Part) -> void:
	part.status = Part.Status.SHIPPED
	var contract := GameData.get_contract(part.contract_id)
	# Design doc Section 9, escalation point 2: "if it ships anyway, or sits
	# long enough that it ships... the part does not count toward the order."
	# The fix paths now exist (GameData.mortar_patch_defect() /
	# redesign_defect() / hire_specialist()), so is_defective alone still being
	# the right check here just means: whatever the reason, this Part reached
	# Ship still unresolved. The other half of that sentence, "the reputation
	# hit lands on the contract," now lands for real via
	# report_lost_defective_shipment() - Reputation (Section 8) is built.
	if part.is_defective:
		GameData.report_lost_defective_shipment(contract)
		GameData.unregister_part(part)
		status_label.text = "Lost part #%d to an unresolved %s defect (%s)" % [
			part.part_id,
			GameData.DEFECT_CATEGORY_LABEL[part.defect_category],
			contract.customer_name if contract != null else "no contract",
		]
		return
	GameData.credit_contract_shipment(contract, part)
	GameData.unregister_part(part)
	status_label.text = "Shipped part #%d (%s)" % [
		part.part_id, contract.customer_name if contract != null else "no contract"
	]


## Entry station only, unstaffed IDLE: creates a new Part for whichever
## active contract is first in line (no per-station contract picker - see
## the Menu Overlay's Contracts tab) and starts the timer. Called from
## StationDetailMenu's Queue button. Also gated on can_start_new_work() now -
## see that method's comment.
func queue_new_part() -> bool:
	if current_state != State.IDLE or not is_pipeline_entry:
		return false
	if not can_start_new_work():
		return false
	return _try_create_part()


## Bug fix (this session): whether it's actually worth making a brand new
## Part right now, rather than just always saying yes whenever the active
## slot happens to be free. Two backpressure checks, both first-pass
## placeholders since the design doc gives no concrete numbers, just the
## intent: don't create more work than the very next step can physically
## absorb (next_station.can_accept_part() - its rack AND active slot both
## full means genuinely nowhere for a new Part to go but an ever-growing
## Awaiting Transfer pile), and don't create more work while the player
## already has GameData.MAX_UNRESOLVED_DEFECTS_BEFORE_PAUSE-or-more flagged
## Parts sitting unaddressed anywhere in the shop. Used by both
## queue_new_part() (manual) and _auto_queue_if_possible() (staffed
## entry stations) - the two only places a Part is ever conjured from
## nothing rather than received from an upstream station.
func can_start_new_work() -> bool:
	if next_station != null and not next_station.can_accept_part():
		return false
	if GameData.count_unresolved_defects() >= GameData.MAX_UNRESOLVED_DEFECTS_BEFORE_PAUSE:
		return false
	return true


## Manual action: takes a READY part off the station and into GameData's
## Awaiting Transfer holding inventory, freeing the station up for new work.
## Available whenever this station's OWN assigned technician isn't currently
## the one physically standing here to handle it themselves - not just when
## fully unstaffed. A technician can be assigned to several stations and
## spend a long stretch working elsewhere (see Technician.pick_next_station());
## previously this was hidden the instant ANY technician was assigned here at
## all, which meant a Ready Part at a staffed-but-currently-neglected station
## had no way out except waiting for that technician to eventually cycle back
## around - reported as "there's no way for parts to make it to ship."
func collect_ready_part() -> bool:
	if is_technician_present():
		return false

	if is_parallel_shelling():
		if shelling_ready_parts.is_empty():
			return false
		var part: Part = shelling_ready_parts.pop_front()
		GameData.hold_part(part)
		_update_parallel_state()
		_fill_active_slot_if_possible()
		_update_display()
		return true

	if current_state != State.READY or current_part == null:
		return false

	var part := current_part
	current_part = null
	current_state = State.IDLE
	GameData.hold_part(part)
	_fill_active_slot_if_possible()
	_update_display()
	return true


## Called from StationDetailMenu's batch size control (BATCHED stations only).
func set_batch_size(value: int) -> void:
	batch_size = value


## Design doc Section 21.6, "the one case where not proceeding makes sense" -
## removes part from wherever it's physically sitting at this Station
## (current_part, queue_rack, or the parallel-shelling arrays), freeing up
## the slot it was occupying same as a normal collect/send would. Does NOT
## touch GameData.active_parts/held_parts - see GameData.scrap_part_for_expertise()
## for the bookkeeping half; StationDetailMenu's scrap handler calls both.
## Returns whether part was actually found and removed here.
func remove_part(part: Part) -> bool:
	if current_part == part:
		current_part = null
		current_state = State.IDLE
		_fill_active_slot_if_possible()
		_update_display()
		return true
	if queue_rack.has(part):
		queue_rack.erase(part)
		_update_display()
		return true
	for run in shelling_active_parts:
		if run.part == part:
			shelling_active_parts.erase(run)
			_update_parallel_state()
			_fill_active_slot_if_possible()
			_update_display()
			return true
	if shelling_ready_parts.has(part):
		shelling_ready_parts.erase(part)
		_update_parallel_state()
		_update_display()
		return true
	return false


## Spends currency to raise current_tier by one, if not already maxed and
## affordable. Only changes current_tier/sprite for now - Tier 2-5 don't yet
## shorten timer_duration or raise batch_cap, that's a later pass. Called
## from StationDetailMenu's Upgrade button.
func try_upgrade() -> bool:
	if current_tier >= 5:
		return false
	var target := current_tier + 1
	if not GameData.try_spend(GameData.upgrade_cost_for_tier(target)):
		return false
	current_tier = target
	_apply_tier_batch_effects()
	return true


## Design doc Section 21.1: rack capacity is its own purchase, fully separate
## from current_tier - see rack_capacity's own comment above. Called from
## StationDetailMenu's Upgrade Rack button.
func try_upgrade_rack() -> bool:
	if rack_capacity >= MAX_RACK_CAPACITY:
		return false
	var target := rack_capacity + 1
	if not GameData.try_spend(GameData.rack_upgrade_cost_for(target)):
		return false
	rack_capacity = target
	return true


## Station-specific tier effects (design doc Section 4: "printer tiers add
## per-printer batching... Shelling tiers add parallel independent timers
## rather than a shared batch timer... Abrasive Blast tiers unlock batching
## that does not exist at Tier 1"). For Shelling, batch_cap is repurposed as
## the parallel-run cap (how many independent ShellingRuns at once) rather
## than a shared-timer batch size - see is_parallel_shelling(). Every other
## BATCHED station's batch_cap stays flat at its Tier 1 value - Section 21.8
## only calls out these three cases, general per-tier batch growth for
## everything else is still "not built yet."
func _apply_tier_batch_effects() -> void:
	if station_id.begins_with("printing"):
		batch_cap = GameData.PRINTER_TIER_BATCH_CAP.get(current_tier, batch_cap)
	elif station_id == "abrasive_blast":
		batch_cap = GameData.ABRASIVE_BLAST_TIER_BATCH_CAP.get(current_tier, batch_cap)
	elif station_id == "shelling":
		batch_cap = GameData.SHELLING_TIER_PARALLEL_CAP.get(current_tier, batch_cap)
		if is_parallel_shelling():
			_migrate_to_parallel_shelling()


## Called from StationDetailMenu's Push Through checkbox (Pour only - see
## StationDetailMenu._refresh(), which only shows it for station_id=="pour").
func set_push_through_armed(value: bool) -> void:
	push_through_armed = value


## Low-level wiring only - actually staffing a station is GameData.assign_technician(),
## which also keeps tech.assigned_station_ids in sync. This is what that
## calls once the roster bookkeeping is done: from here on the station
## creates/sends parts on its own - no tap needed. _process() picks up
## routing/auto-queue on its own the very next frame once presence is
## resolved (see _technician_act()), so this only needs to handle the one
## thing that wouldn't otherwise happen on its own: catching up a backlog of
## Awaiting Transfer Parts that were waiting specifically for this station to
## get staffed. Design request, this session: idempotent append rather than
## a straight assignment now that several technicians can be assigned here
## at once (assigned_technicians' own comment) - doesn't evict whoever else
## is already assigned.
func assign_technician(tech: Technician) -> void:
	if not assigned_technicians.has(tech):
		assigned_technicians.append(tech)
	_update_display()
	_claim_held_parts_bound_here()


## A Part only ever lands in GameData.held_parts because its next station
## wasn't staffed (or automatic) at the moment it was ready - see
## _try_send_to_next_station()'s "not next_is_reachable" branch, and manual
## Collect. Nothing was re-checking that holding pile once staffing caught
## up, so a Part could get stuck in Awaiting Transfer forever even after a
## technician arrived here. Sweeps for any Parts specifically waiting on
## THIS station and pulls them in now, up to capacity - called both right
## when this station becomes staffed (to catch up a whole backlog at once,
## up to the rack's capacity) and from _fill_active_slot_if_possible() (so
## any overflow beyond that keeps draining as the station cycles through
## work, the same way it would for newly-arriving parts). Returns whether
## it claimed anything.
func _claim_held_parts_bound_here() -> bool:
	var claimed_any := false
	for part in GameData.held_parts.duplicate():
		if GameData.next_station_id_for(part) != station_id:
			continue
		if not can_accept_part():
			break
		GameData.release_held_part(part)
		receive_part(part)
		claimed_any = true
	return claimed_any


## Low-level wiring only, see assign_technician() above - call
## GameData.unassign_technician() instead so the roster stays in sync. If
## tech happened to be the active_worker, releases that slot too so whoever
## else is still assigned (and present) can claim it.
func unassign_technician(tech: Technician) -> void:
	assigned_technicians.erase(tech)
	if active_worker == tech:
		active_worker = null
	_update_display()


## Entry station only: creates a new Part for the given contract (or, if
## none is given, whichever active contract is first in line - there's no
## per-station contract picker anymore, see the Contracts menu tab instead)
## and starts the timer. Fails if a part is already in progress here, or no
## contract is available to assign it to.
func _try_create_part(contract: Contract = null) -> bool:
	if current_part != null:
		return false
	if contract == null:
		var active := GameData.get_active_contracts()
		if active.is_empty():
			return false
		contract = active[0]

	# Section 24.1: a contract can have several line items - pick whichever
	# one still needs more Parts (shipped-or-in-flight, not just shipped, so
	# this doesn't keep overproducing one line item past what it actually
	# needs while another on the same contract still needs work). No open
	# line item (everything already shipped or covered by Parts already in
	# the pipeline) means there's genuinely nothing to create yet - same as
	# the old "contract has no room" case, just resolved per line item now.
	var in_flight := GameData.in_flight_counts_for_contract(contract.contract_id)
	var line_item_index := contract.first_open_line_item_index(in_flight)
	if line_item_index < 0:
		return false

	var part := Part.new()
	part.current_station_index = 0
	part.contract_id = contract.contract_id
	part.line_item_index = line_item_index
	GameData.register_part(part)
	current_part = part
	_start_running()
	_update_display()
	return true


## Hands a ready Part onward - but not by teleporting it there. Ship is the
## one exception (it's always automatic, no technician needed to reach it,
## so this still sends straight there instantly). For every other
## next_station, the technician assigned HERE carries the part themselves if
## they can: they pick it up only if they're also assigned to next_station
## (see Technician.assigned_station_ids) - otherwise they'd never actually
## walk it there - and only if their own limited carried_parts has room
## (Technician.CARRY_CAPACITY). A picked-up part leaves this station
## immediately but doesn't arrive at next_station until the technician's
## rotation physically brings them there - see _deposit_carried_parts()
## below, called on every station they visit.
##
## If THIS technician can't personally carry it (not assigned to
## next_station, or already carrying as much as they can), the part falls
## back to the shared Awaiting Transfer pool instead of blocking here
## forever - same as an unstaffed station's manual Collect. Whoever ends up
## staffing next_station (any technician, not necessarily this one) then
## auto-claims it the moment their own slot needs filling, see
## _claim_held_parts_bound_here(). Without this fallback, the single most
## natural staffing setup - one technician per station, nobody deliberately
## double-covering adjacent stations - would silently stall the entire
## pipeline after the first station, since no one tech would ever be
## assigned to both halves of any handoff.
func _try_send_to_next_station(tech: Technician) -> bool:
	if not _has_ready_part_to_send():
		return false
	if next_station == null:
		return false

	var part := shelling_ready_parts[0] if is_parallel_shelling() else current_part

	if next_station.station_type == StationType.AUTOMATIC:
		if not next_station.can_accept_part():
			status_label.text = "Next station busy, try again"
			return false
		_clear_sent_ready_part(part)
		next_station.receive_part(part)
		_update_display()
		return true

	var can_personally_carry := (
		tech.carried_parts.size() < Technician.CARRY_CAPACITY
		and tech.real_assigned_station_ids().has(next_station.station_id)
	)

	_clear_sent_ready_part(part)
	if can_personally_carry:
		tech.carried_parts.append(part)
	else:
		GameData.hold_part(part)
	_update_display()
	return true


## Removes part from wherever it was sitting ready (current_part, or the
## front of shelling_ready_parts for parallel shelling - design doc Section
## 21.4) as the shared last step of _try_send_to_next_station() above,
## regardless of whether it's headed to Ship, a technician's carry inventory,
## or Awaiting Transfer.
func _clear_sent_ready_part(part: Part) -> void:
	if is_parallel_shelling():
		shelling_ready_parts.erase(part)
		_update_parallel_state()
	else:
		current_part = null
		current_state = State.IDLE


## Technician-carried handoff, dropoff half (pickup is in
## _try_send_to_next_station() above): while physically present, hands over
## ONE part the technician is carrying that belongs here - i.e. something
## they picked up on a previous visit to wherever it came from, now actually
## delivered because their rotation brought them to this station. Only one
## per call, same as every other technician action - see _technician_act(),
## which re-calls this on the next interact cycle if they're carrying more
## than one thing bound here.
func _deposit_one_carried_part(tech: Technician) -> bool:
	for part in tech.carried_parts:
		if GameData.next_station_id_for(part) != station_id:
			continue
		if not can_accept_part():
			return false
		tech.carried_parts.erase(part)
		receive_part(part)
		return true
	return false


## Called whenever the active slot is free (or just freed up). Tries, in
## order: the queue rack, then GameData.held_parts (Parts stuck waiting
## specifically for this station - see _claim_held_parts_bound_here()
## below), and only as a last resort conjures a brand new Part from nothing
## (staffed entry stations only). The held_parts claim and auto-queue steps
## are plain queue mechanics / automation that happen regardless of physical
## technician presence, same as always. The RACK step is different: a
## STAFFED station only pulls from its own queue_rack when the active worker
## is actually standing here right now (is_technician_present()) - a real
## machine doesn't load itself. An unstaffed station (nobody assigned at all)
## still drains its rack immediately, same as before. Returns whether it
## actually loaded something.
func _fill_active_slot_if_possible() -> bool:
	if is_parallel_shelling():
		return _fill_parallel_slot_if_possible()
	if current_part != null:
		return false
	if not queue_rack.is_empty() and (assigned_technicians.is_empty() or is_technician_present()):
		current_part = queue_rack.pop_front()
		_start_running()
		_update_display()
		return true
	if _claim_held_parts_bound_here():
		return true
	return _auto_queue_if_possible()


## Parallel-shelling equivalent of _fill_active_slot_if_possible() above -
## same ordering (rack first, then held parts, then auto-queue), just against
## an open ShellingRun slot instead of the single current_part.
func _fill_parallel_slot_if_possible() -> bool:
	if not _has_open_slot_to_fill():
		return false
	if not queue_rack.is_empty() and (assigned_technicians.is_empty() or is_technician_present()):
		_start_shelling_run(queue_rack.pop_front())
		return true
	if _claim_held_parts_bound_here():
		return true
	return _auto_queue_if_possible()


## Staffed entry station, idle, nothing in progress: keep the line moving
## by starting a new part for whichever active contract is first in line.
## There's no UI yet for a technician to prefer a specific contract.
func _auto_queue_if_possible() -> bool:
	if not (is_pipeline_entry and active_worker != null and current_part == null):
		return false
	if not can_start_new_work():
		return false
	var active := GameData.get_active_contracts()
	if active.is_empty():
		return false
	return _try_create_part(active[0])


func _update_sprite() -> void:
	_has_state_art = state_sprites.size() >= 3
	if _has_state_art:
		_apply_state_sprite()
		return

	_has_tiered_art = tier_sprites.size() >= current_tier and tier_sprites[current_tier - 1] != null
	if _has_tiered_art:
		station_sprite.texture = tier_sprites[current_tier - 1]
		station_sprite.modulate = Color.WHITE
	else:
		station_sprite.texture = _get_placeholder_texture()
		_apply_state_tint()


## Picks the right state_sprites frame. Bug fix (design feedback: "it should
## be closed when the technician leaves the station"): the machine now
## defaults to frame 0 (closed) at all times, in every one of IDLE/RUNNING/
## READY - not one open frame while running and a different open frame while
## ready, which read as the lid just being left open unattended (like running
## a dishwasher with the door open). state_sprites[1]/[2] (open) only ever
## appear during the interaction flourish itself, while a technician is
## physically mid-interaction here (see INTERACT_ANIM_FRAME_SECONDS's
## comment) - open only because someone's actually there with their hands in
## it, closed the rest of the time, including the instant they walk away.
func _apply_state_sprite() -> void:
	station_sprite.modulate = Color.WHITE
	if _is_interact_animating():
		var frame := int(_interact_anim_elapsed / INTERACT_ANIM_FRAME_SECONDS)
		station_sprite.texture = state_sprites[clampi(frame, 0, state_sprites.size() - 1)]
		return
	station_sprite.texture = state_sprites[0]


func _is_interact_animating() -> bool:
	return active_worker != null and active_worker.is_interacting


## Shared by both _update_display() call sites below - whichever one of the
## three art systems this station actually has (real per-state art, tiered
## art, or the generic tinted placeholder) gets refreshed on a state change.
func _refresh_state_visual() -> void:
	if _has_state_art:
		_apply_state_sprite()
	elif not _has_tiered_art:
		_apply_state_tint()


## The 8 stations with no real art yet (see tier_sprites) previously rendered
## as a bare 64x64 white square - at BASE_SPRITE_SCALE (0.18) that's an
## ~11px dot, basically invisible next to Burnout/Pour's real ~1254px photo
## assets rendering at the same scale (~225px). Sized to roughly match that
## instead (220x220), plus a baked-in border so it still reads as "a station"
## rather than a flat blob even before _apply_state_tint()'s modulate color
## is applied on top.
const PLACEHOLDER_SIZE: int = 220
const PLACEHOLDER_BORDER: int = 10
const PLACEHOLDER_BORDER_COLOR: Color = Color(0.25, 0.15, 0.08)

func _get_placeholder_texture() -> ImageTexture:
	var image := Image.create(PLACEHOLDER_SIZE, PLACEHOLDER_SIZE, true, Image.FORMAT_RGBA8)
	image.fill(PLACEHOLDER_BORDER_COLOR)
	image.fill_rect(Rect2i(
		PLACEHOLDER_BORDER, PLACEHOLDER_BORDER,
		PLACEHOLDER_SIZE - PLACEHOLDER_BORDER * 2, PLACEHOLDER_SIZE - PLACEHOLDER_BORDER * 2
	), Color.WHITE)
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## Starts the timer for whatever Part just entered this station. If staffed,
## the technician's current productivity_multiplier (design doc Section 7 -
## lower when they're spread across more than one station) stretches the
## effective run time; unstaffed stations always run at the base
## timer_duration, a human's own speed isn't modeled as a multiplier. Applied
## once per run, at start - if the technician's station count changes
## mid-run, it only affects their next cycle here, not the one in progress.
func _start_running() -> void:
	if push_through_armed and GameData.PUSH_THROUGH_ELIGIBLE_STATIONS.has(station_id) and current_part != null:
		current_part.is_push_through = true
		push_through_armed = false
	current_state = State.RUNNING
	var effective_duration := _effective_timer_duration()
	timer_bar.max_value = effective_duration
	station_timer.wait_time = max(effective_duration, 0.01)
	station_timer.start()


func _effective_timer_duration() -> float:
	if active_worker == null:
		return max(timer_duration, 0.01)
	return max(timer_duration / active_worker.productivity_multiplier, 0.01)


func _on_station_timer_timeout() -> void:
	if current_part != null and current_part.is_push_through:
		_resolve_push_through(current_part)
		return
	current_state = State.READY
	if current_part != null:
		current_part.status = Part.Status.READY_TO_ROUTE
		_maybe_flag_defect(current_part)
		if station_id == "patching":
			_resolve_patching(current_part)
	_update_display()
	# No direct _try_send_to_next_station() call here - if a technician is
	# present, _process()'s next frame picks this up via _technician_act()
	# same as any other state change, one single path instead of two.


## Design doc Section 21.4: "every part passes through here, not just flagged
## ones... Auto-resolves any printer-sourced defect... without a player
## decision." Deterministic, not a risk roll - Patching itself never rolls
## for a NEW defect (it has no entry in GameData.STATION_BASE_DEFECT_RISK, so
## the _maybe_flag_defect() call above this is already a no-op for it), and
## the doc gives Patching no failure case of its own, unlike every real
## defect-roll station. "printer-sourced" specifically means Printing, not
## any defect that happens to still be flagged when a part reaches here (a
## Shelling-origin defect can't happen yet at this point in the pipeline
## anyway - Patching sits before Shelling - but this check is what makes that
## explicit rather than accidental). For an unflagged part this is a no-op,
## matching "still a real pass" either way.
##
## "Outcome quality scales with the assigned technician's skill" (21.4) is
## realized through the existing generic productivity_multiplier speed
## scaling (_effective_timer_duration(), same mechanism every station already
## uses) rather than a new stochastic quality/failure roll - Patching isn't a
## defect-risk station, so Technician.defect_multiplier has no natural
## meaning here the way it does at Printing/Shelling/Burnout/Pour. A richer
## "low-skill technician does a worse smoothing job" mechanic is a reasonable
## future direction but isn't specified with enough detail in Section 21 to
## implement without inventing numbers wholesale.
func _resolve_patching(part: Part) -> void:
	if part.is_defective and part.defect_station_id.begins_with("printing"):
		part.clear_defect()


## Rolls for a defect the instant a part finishes running here (design doc
## Section 9) - combined risk is base station risk x this part's contract's
## geometry familiarity multiplier x the assigned technician's skill
## multiplier (1.0, no reduction, if unstaffed - matching Section 9's "Manual
## or Apprentice" row, neither gets any risk reduction), plus a hired
## specialist's mitigation (see _roll_defect_outcome() below). This only
## flags the defect - clearing it is one of the three fix paths on GameData
## (mortar_patch_defect() / redesign_defect() / hire_specialist()) - and the
## Reputation consequence lands for real at Ship if it's still unresolved by
## then (see _ship_part() / GameData.report_lost_defective_shipment()).
func _maybe_flag_defect(part: Part) -> void:
	var category := _roll_defect_outcome(part)
	if category == GameData.DefectCategory.NONE:
		return
	part.flag_defect(category, station_id, GameData.grace_period_seconds_for(station_id))


## Shared by _maybe_flag_defect() (normal run) and _resolve_push_through()
## (Pour's Push Through, which rolls these exact same odds - "normal odds
## apply, success or failure" per Section 9 - but reacts to a hit
## differently). Returns the rolled category, or NONE if no defect happens
## at all this time. A specialist's mitigation is applied AFTER the category
## is chosen, not folded into the base risk multiply, because a station like
## Burnout rolls between two categories covered by two different specialist
## types (Warping -> Pattern Specialist, Shell Crack -> Shell Specialist) -
## which one matters isn't known until the category roll itself.
func _roll_defect_outcome(part: Part) -> int: # GameData.DefectCategory
	var base_risk := GameData.base_defect_risk_for(station_id)
	if base_risk <= 0.0:
		return GameData.DefectCategory.NONE
	var familiarity_mult := GameData.familiarity_multiplier_for(
		GameData.geometry_name_for_part(part), station_id
	)
	var tech_mult := (
		active_worker.defect_multiplier if active_worker != null else 1.0
	)
	var risk := base_risk * familiarity_mult * tech_mult
	if randf() >= risk:
		return GameData.DefectCategory.NONE
	var category := GameData.roll_defect_category(station_id)
	if category == GameData.DefectCategory.NONE:
		return GameData.DefectCategory.NONE
	if GameData.has_specialist_for(category) and randf() < GameData.SPECIALIST_RISK_MULTIPLIER:
		return GameData.DefectCategory.NONE
	return category


## Design doc Section 9/21.6, "Push Through": now generalized beyond Pour to
## every station in GameData.PUSH_THROUGH_ELIGIBLE_STATIONS (Shelling,
## Burnout, Mold Prep, Pour). "Normal odds apply, success or failure, but a
## push through always grants a bigger familiarity jump than a normal
## completed part would, win or lose... it costs you the part on a failure."
## Familiarity rises either way before the outcome is even known, matching
## "win or lose" - now raised specifically at THIS station (station_id) per
## Section 21.7's per-station familiarity, not a blanket score. A hit
## destroys the part outright (unregistered, never reaches Ship) instead of
## just flagging it, since a flagged Part can still be fixed and shipped,
## which isn't what "costs you the part" describes - this also already
## covers "an unfixable Burnout defect... is kept only as a familiarity
## trial" (21.6) for free, since Push Through already always destroys the
## part on any failure regardless of which station it happened at, no
## Burnout-specific logic needed.
func _resolve_push_through(part: Part) -> void:
	part.is_push_through = false
	GameData.raise_familiarity(
		GameData.geometry_name_for_part(part), station_id, GameData.FAMILIARITY_GAIN_PUSH_THROUGH
	)
	var outcome := _roll_defect_outcome(part)

	if is_parallel_shelling():
		if outcome == GameData.DefectCategory.NONE:
			part.status = Part.Status.READY_TO_ROUTE
			shelling_ready_parts.append(part)
			status_label.text = "Push Through succeeded on part #%d%s" % [part.part_id, _rack_suffix()]
		else:
			GameData.unregister_part(part)
			status_label.text = "Push Through failed - lost part #%d to %s%s" % [
				part.part_id, GameData.DEFECT_CATEGORY_LABEL[outcome], _rack_suffix()
			]
		_update_parallel_state()
		_update_display()
		return

	_clear_timer_bar()
	if outcome == GameData.DefectCategory.NONE:
		current_state = State.READY
		part.status = Part.Status.READY_TO_ROUTE
		status_label.text = "Push Through succeeded on part #%d%s" % [part.part_id, _rack_suffix()]
		return
	current_part = null
	current_state = State.IDLE
	GameData.unregister_part(part)
	status_label.text = "Push Through failed - lost part #%d to %s%s" % [
		part.part_id, GameData.DEFECT_CATEGORY_LABEL[outcome], _rack_suffix()
	]
	_fill_active_slot_if_possible()


func _clear_timer_bar() -> void:
	timer_bar.value = 0.0
	timer_bar_label.text = ""


func _apply_state_tint() -> void:
	match current_state:
		State.IDLE:
			station_sprite.modulate = Color.WHITE
		State.RUNNING:
			station_sprite.modulate = Color.YELLOW
		State.READY:
			station_sprite.modulate = Color.GREEN


## Floor-level display only now - no buttons live here anymore, see
## StationDetailMenu for every player action.
func _update_display() -> void:
	if station_type == StationType.AUTOMATIC:
		status_label.text = "Waiting for parts to arrive"
		_clear_timer_bar()
		return

	if is_parallel_shelling():
		status_label.text = _parallel_shelling_status_text() + _rack_suffix() + _defect_suffix()
		_refresh_state_visual()
		return

	match current_state:
		State.IDLE:
			_clear_timer_bar()
			status_label.text = "Idle" if is_pipeline_entry else "Waiting for part"
		State.RUNNING:
			status_label.text = "Running"
		State.READY:
			_clear_timer_bar()
			status_label.text = "Ready" if active_worker != null else "Ready - awaiting collection"
	status_label.text += _rack_suffix()
	status_label.text += _defect_suffix()

	_refresh_state_visual()


## "2/3 running, 1 ready" - design doc Section 21.4's parallel shelling model
## can have several Parts simultaneously mid-run and/or simultaneously done,
## which a single IDLE/RUNNING/READY line can't represent precisely - shared
## by the floor status label and get_overview_status() below.
func _parallel_shelling_status_text() -> String:
	if shelling_active_parts.is_empty() and shelling_ready_parts.is_empty():
		return "Idle"
	var parts: Array[String] = []
	if batch_cap > 0:
		parts.append("%d/%d running" % [shelling_active_parts.size(), batch_cap])
	if not shelling_ready_parts.is_empty():
		parts.append("%d ready" % shelling_ready_parts.size())
	return ", ".join(PackedStringArray(parts))


## " (+N waiting)" when the queue rack has Parts buffered behind the active
## one, otherwise empty - shared by the floor status label and Overview tab.
func _rack_suffix() -> String:
	if queue_rack.is_empty():
		return ""
	return " (+%d waiting)" % queue_rack.size()


## " - DEFECT: <category> (<Xs to address> / ESCALATED)" when current_part is
## flagged (design doc Section 9), otherwise empty - shared by the floor
## status label, the Overview tab, and the Station Detail Menu (which reads
## its main status line from get_overview_status(), same as Overview). A
## defect flagged at an EARLIER station stays visible here too - nothing
## clears defect_category until the fix paths exist (next pass), so it rides
## along with the Part for the rest of its trip.
func _defect_suffix() -> String:
	if is_parallel_shelling():
		return _defect_suffix_parallel()
	if current_part == null or not current_part.is_defective:
		return ""
	var label: String = GameData.DEFECT_CATEGORY_LABEL[current_part.defect_category]
	if current_part.defect_escalated:
		return " - DEFECT: %s (ESCALATED)" % label
	return " - DEFECT: %s (%.0fs to address)" % [label, current_part.defect_time_remaining]


## Parallel shelling can have several Parts flagged at once across
## shelling_active_parts/shelling_ready_parts - a single category/countdown
## line doesn't generalize the way it does for one current_part, so this just
## surfaces a count; per-part detail is available from the rack panel and
## Station Detail Menu's defect row (see StationDetailMenu._refresh_defect_row()).
func _defect_suffix_parallel() -> String:
	var count := 0
	for run in shelling_active_parts:
		if run.part.is_defective:
			count += 1
	for part in shelling_ready_parts:
		if part.is_defective:
			count += 1
	if count == 0:
		return ""
	return " - %d part(s) flagged with defects" % count


## Overview menu tab text for this station's current state. Ship never runs
## a timer of its own - it credits and discards a part the instant it
## arrives - so it gets its own fixed description instead of an idle/ready read.
func get_overview_status() -> String:
	if station_type == StationType.AUTOMATIC:
		return "Automatic - ships parts on arrival"
	if is_parallel_shelling():
		return _parallel_shelling_status_text() + _current_part_suffix() + _rack_suffix() + _defect_suffix()

	var status: String
	match current_state:
		State.IDLE:
			status = "Idle"
		State.RUNNING:
			status = "Running (%.1fs left)" % station_timer.time_left
		State.READY:
			status = "Ready - awaiting collection" if active_worker == null else "Ready"
		_:
			status = ""
	return status + _current_part_suffix() + _rack_suffix() + _defect_suffix()


## Design request, this session: "see which part is currently being worked
## on at each station." Shared by the Menu Overlay's Overview tab and the
## Station Detail Menu's main status line (both read get_overview_status()) -
## deliberately NOT added to the floor's own compact status label, which is
## already tight on space at a small pixel-font size; this info is one tap
## away in either of those two more detailed views instead.
func _current_part_suffix() -> String:
	if is_parallel_shelling():
		var ids: Array[String] = []
		for run in shelling_active_parts:
			ids.append("#%d" % run.part.part_id)
		for part in shelling_ready_parts:
			ids.append("#%d" % part.part_id)
		if ids.is_empty():
			return ""
		return " [%s]" % ", ".join(PackedStringArray(ids))
	if current_part == null:
		return ""
	var contract := GameData.get_contract(current_part.contract_id)
	return " - Part #%d (%s)" % [
		current_part.part_id, contract.customer_name if contract != null else "no contract"
	]
