extends Resource
class_name Technician

## A hired technician, living on GameData.technicians (the Shop's roster)
## independent of whether they're currently working anywhere. Assigning one
## to a Station is a separate step - see GameData.assign_technician() - and
## a single technician can be assigned to more than one Station at once
## (design doc Section 7, Multi-station assignment and the walking penalty).

enum SkillTier { APPRENTICE, TECHNICIAN, SENIOR_TECHNICIAN, MASTER }

const TIER_LABEL := {
	SkillTier.APPRENTICE: "Apprentice",
	SkillTier.TECHNICIAN: "Technician",
	SkillTier.SENIOR_TECHNICIAN: "Senior Technician",
	SkillTier.MASTER: "Master",
}

## The design doc only gives Hire Cost / Wage as qualitative Low-Highest
## per tier (Section 6); these are first-pass placeholder numbers scaled
## roughly 2-2.5x per tier, same spirit as the Tier 1->5 upgrade cost note
## in Section 16. Tune once the real economy lands.
const TIER_HIRE_COST := {
	SkillTier.APPRENTICE: 50,
	SkillTier.TECHNICIAN: 150,
	SkillTier.SENIOR_TECHNICIAN: 400,
	SkillTier.MASTER: 900,
}
const TIER_WAGE := {
	SkillTier.APPRENTICE: 5,
	SkillTier.TECHNICIAN: 15,
	SkillTier.SENIOR_TECHNICIAN: 35,
	SkillTier.MASTER: 75,
}

## Defect rate multiplier, concrete numbers from Section 9's
## "Technician Skill" table (Manual/Apprentice=100% down to Master=55%).
## Actually applied in Station._maybe_flag_defect() - see CLAUDE.md's
## "Quality, Defects, and Geometry Familiarity" section.
const TIER_DEFECT_MULTIPLIER := {
	SkillTier.APPRENTICE: 1.0,
	SkillTier.TECHNICIAN: 0.85,
	SkillTier.SENIOR_TECHNICIAN: 0.70,
	SkillTier.MASTER: 0.55,
}

## First-pass placeholder walking penalty (Section 7) - deliberately reuses
## the same 100/85/70/55 shape as TIER_DEFECT_MULTIPLIER above, keyed by
## station count instead of skill tier. One station is full productivity;
## every station beyond that costs more, flooring out at 4+.
const STATION_COUNT_PRODUCTIVITY := {
	1: 1.0,
	2: 0.85,
	3: 0.70,
}
const MIN_PRODUCTIVITY: float = 0.55

## Design request, this session: "printing, shelling, and pour will be
## engineer skills" - Engineer is a new role on this same class (not a new
## class, and not a repurposing of the separate one-time Specialist hire -
## Engineers are hired/wagd/assigned/walk-around exactly like a Technician
## does today; `role` only changes which departments they roll skill in and
## which stations that skill actually protects). `SkillTier` and its hire
## cost/wage/defect-multiplier tables above are shared by both roles - tier
## is orthogonal to role, a "Senior" can be either a Technician or an
## Engineer with the exact same hire cost/wage/base defect multiplier.
enum StaffRole { TECHNICIAN, ENGINEER }
@export var role: StaffRole = StaffRole.TECHNICIAN

const ROLE_LABEL := {
	StaffRole.TECHNICIAN: "Technician",
	StaffRole.ENGINEER: "Engineer",
}

## Burnout and Mold Prep are deliberately absent - the user named exactly
## these 5 departments; Burnout/Mold Prep keep today's existing tier-only
## defect_multiplier + shop-wide GameData.geometry_familiarity behavior
## completely unchanged (see GameData.department_for_station()).
## "post_process" covers Deshell/Abrasive Blast/Ship and the new Grinding
## station as one skill, matching the mockup's own 3-department grouping
## once Pour moves under Engineer instead.
const ENGINEER_DEPARTMENTS: Array[String] = ["printing", "shelling", "pour"]
const TECHNICIAN_DEPARTMENTS: Array[String] = ["patching", "post_process"]

func departments() -> Array[String]:
	return ENGINEER_DEPARTMENTS if role == StaffRole.ENGINEER else TECHNICIAN_DEPARTMENTS


## First-pass placeholder tier-scaled roll range for department_skill below -
## a higher tier is *usually* better but not deterministically uniform
## (design request: "i want the technicians to be random in the skills they
## possess") - each department gets its own independent roll within this
## range, so e.g. an Apprentice can still roll a genuinely strong department
## alongside a weak one, same shape as the reference mockup's own uneven
## per-department spreads even within one tier.
const TIER_SKILL_ROLL_RANGE := {
	SkillTier.APPRENTICE: Vector2i(0, 2),
	SkillTier.TECHNICIAN: Vector2i(1, 3),
	SkillTier.SENIOR_TECHNICIAN: Vector2i(2, 4),
	SkillTier.MASTER: Vector2i(3, 5),
}

## department_name -> 0-5 stars, one independent roll per entry in
## departments() at hire time (see roll_department_skills() below) - never
## re-rolled afterward. This is the hire's "skill rating" shown before
## they've worked on anything, and doubles as their STARTING per-geometry
## familiarity baseline - see familiarity_for_geometry() below ("the skill
## rating you see is the familiarity baseline they have of all geometries").
var department_skill: Dictionary = {}


## Called once, right after this Technician resource is created (a direct
## hire or a rolled applicant-pool candidate - see GameData) - one
## independent roll per department this role actually has.
func roll_department_skills() -> void:
	var skill_range: Vector2i = TIER_SKILL_ROLL_RANGE[skill_tier]
	for department in departments():
		department_skill[department] = randi_range(skill_range.x, skill_range.y)


## The shop-wide familiarity summary (GameData.average_familiarity_stars()/
## weakest_familiarity_stars()) needs one number per worker per geometry
## without knowing which specific station/department is relevant - a
## contract's geometry can touch several of this worker's stations. Falls
## back to the average of every department this worker actually has a
## skill in, rather than any one specific department.
func average_department_skill() -> float:
	if department_skill.is_empty():
		return 0.0
	var total := 0.0
	for value in department_skill.values():
		total += value
	return total / department_skill.size()


func shopwide_familiarity_for_geometry(geometry_name: String) -> float:
	if geometry_familiarity.has(geometry_name):
		return float(geometry_familiarity[geometry_name])
	return average_department_skill()

## geometry_name -> 0-5 stars, starts empty. Personal, hands-on familiarity -
## "each time they process a part of a certain geometry they gain some
## amount of familiarity with that geometry" - distinct from the flat
## department_skill baseline above, which never changes after hire.
var geometry_familiarity: Dictionary = {}

## Falls back to this worker's department_skill baseline until real
## hands-on experience with this specific geometry has actually been
## recorded (gain_experience() below) - a brand new hire is only ever as
## good as their rolled department skill at every geometry they haven't
## touched yet, exactly matching "the skill rating you see IS the
## familiarity baseline."
func familiarity_for_geometry(geometry_name: String, department_name: String) -> int:
	if geometry_familiarity.has(geometry_name):
		return geometry_familiarity[geometry_name]
	return department_skill.get(department_name, 0)


func gain_experience(geometry_name: String, department_name: String, amount: int) -> void:
	var current := familiarity_for_geometry(geometry_name, department_name)
	geometry_familiarity[geometry_name] = clampi(current + amount, 0, 5)

## Design doc Section 7, "Routing strategy": which of this technician's OTHER
## assigned stations they head to next once there's nothing left to do at
## the current one - see pick_next_station() below. Switchable per-technician
## from the Shop's Technicians tab; doesn't matter at all for a
## single-station technician, only when they're covering 2+.
enum RoutingStrategy { PUSH_THROUGH, MAXIMIZE_MACHINES }

const ROUTING_STRATEGY_LABEL := {
	RoutingStrategy.PUSH_THROUGH: "Push Parts Through",
	RoutingStrategy.MAXIMIZE_MACHINES: "Maximize Machines Running",
}

@export var technician_name: String = "Technician"
@export var skill_tier: SkillTier = SkillTier.APPRENTICE
@export var routing_strategy: RoutingStrategy = RoutingStrategy.MAXIMIZE_MACHINES

## Station ids (GameData.StationDef.id) this technician currently works.
## Populated/cleared only via GameData.assign_technician() /
## unassign_technician() so a Station's own assigned_technicians array stays
## in sync. Design request, this session: this can now also contain the
## literal string "printing" - a virtual group entry meaning "every
## currently-owned printer instance," rather than needing one literal
## "printing_N" entry per printer ("I want the print station responsibility
## to cover all the printers not individual ones"). Never read this directly
## when you actually need real, walkable station ids - use
## real_assigned_station_ids() below, which expands that group entry.
var assigned_station_ids: Array[String] = []


## Expands the virtual "printing" group entry above into every printer
## instance id currently owned (GameData.printer_station_ids()), read fresh
## every call rather than snapshotted at assignment time - so a printer
## bought later is automatically covered by anyone already assigned to the
## group, no extra bookkeeping needed. Every other entry already names a
## real Station and passes through unchanged. Use this instead of
## assigned_station_ids directly anywhere the code needs to actually walk to,
## count, or compare against real Stations (tick()'s snap logic,
## productivity_multiplier, pick_next_station(), has_multiple_real_stations()).
func real_assigned_station_ids() -> Array[String]:
	var ids: Array[String] = []
	for id in assigned_station_ids:
		if id == "printing":
			for printer_id in GameData.printer_station_ids():
				if not ids.has(printer_id):
					ids.append(printer_id)
		elif not ids.has(id):
			ids.append(id)
	return ids


## Whether this technician has more than one real, concrete station to
## actually consider walking between - true for someone assigned to the
## "printing" group with 2+ owned printers even though assigned_station_ids
## itself only has that one literal entry.
func has_multiple_real_stations() -> bool:
	return real_assigned_station_ids().size() > 1

## Parts this technician is physically carrying between assigned stations -
## their own small WIP buffer, distinct from a station's queue rack or the
## Awaiting Transfer holding inventory. Deliberately tiny (not unlimited) so
## a technician assigned to several stations can't silently ferry an
## unbounded amount of work between them - see Station._try_send_to_next_station()
## (pickup, gated on carried_parts having room) and _deposit_carried_parts()
## (dropoff, on arrival at the part's next station).
var carried_parts: Array[Part] = []
const CARRY_CAPACITY: int = 2

## Real movement, not an abstract timer: a technician has an actual
## world-space position (same coordinate space as Station.position, see
## main.gd's STATION_POSITIONS) and walks toward a target station at a fixed
## speed, taking however long that real distance actually requires. This is
## what makes a technician a genuine single individual instead of a data
## flag that's simultaneously "at" every assigned station - only wherever
## current_station_id points is actually staffed at any given moment (see
## Station._technician_is_present()), and getting anywhere else takes real,
## distance-proportional time.
const WALK_SPEED: float = 220.0 # pixels/sec, first-pass placeholder

## Brief real pause after actually doing something at a station - depositing
## a carried part, picking one up, or loading the next part into the active
## slot (see Station._technician_act()) - representing physically handling
## it, not idle waiting. There's no fixed "stand around" timer at all: a
## technician assigned to more than one station leaves for the next one the
## moment there's genuinely nothing left to interact with here.
const INTERACT_SECONDS: float = 1.5

## Station id this technician is physically standing at and actively working
## right now - "" if unassigned everywhere or currently mid-walk. While
## is_traveling is true, they are between current_station_id (now "") and
## travel_target_station_id, moving through current_position toward it.
var current_station_id: String = ""
var travel_target_station_id: String = ""
var is_traveling: bool = false
var current_position: Vector2 = Vector2.ZERO

var is_interacting: bool = false
var _interact_elapsed: float = 0.0

var hire_cost: int:
	get: return TIER_HIRE_COST[skill_tier]

var wage: int:
	get: return TIER_WAGE[skill_tier]

var defect_multiplier: float:
	get: return TIER_DEFECT_MULTIPLIER[skill_tier]

var tier_label: String:
	get: return TIER_LABEL[skill_tier]

var role_label: String:
	get: return ROLE_LABEL[role]

var is_assigned: bool:
	get: return not assigned_station_ids.is_empty()

## Effective speed multiplier applied at every station this technician
## works, per the walking penalty - splitting attention across more
## stations means less time actually standing at any one of them. Counts
## real_assigned_station_ids() (every concrete printer counts on its own),
## not the possibly-grouped assigned_station_ids - covering 2 printers via
## the "printing" group is exactly as much of a split-attention commitment
## as being assigned to 2 literally-different stations would be.
var productivity_multiplier: float:
	get:
		var count: int = max(real_assigned_station_ids().size(), 1)
		return STATION_COUNT_PRODUCTIVITY.get(count, MIN_PRODUCTIVITY)


## Advances this technician's real position and interact cooldown by delta
## seconds. Called every frame from GameData._process() for every hired
## technician, given a station_id -> Node2D lookup (GameData.station_by_id,
## populated by main.gd) so travel distance/direction can be computed from
## real station positions. Returns true iff something changed enough to be
## worth a UI refresh (position moved, arrived, started interacting, etc.) -
## the caller uses that to emit technician_updated.
##
## This function only handles movement and the interact cooldown - it never
## decides to start traveling or interacting on its own. Those are Station's
## call: see start_traveling_to() and begin_interacting() below, invoked
## from Station._technician_act() once it knows whether there's real work to
## do here. A technician assigned to zero or one station never leaves - see
## _technician_act(), which only sends someone walking if they have another
## assigned station to check.
func tick(delta: float, station_by_id: Dictionary) -> bool:
	if assigned_station_ids.is_empty():
		if current_station_id == "" and not is_traveling:
			return false
		current_station_id = ""
		is_traveling = false
		is_interacting = false
		return true

	var real_ids := real_assigned_station_ids()
	if real_ids.is_empty():
		# Assigned only to the "printing" group, but zero printers currently
		# owned - shouldn't happen in practice (every shop starts with one),
		# but nothing real to snap onto if it ever did.
		return false

	if not real_ids.has(current_station_id) and not is_traveling:
		# Fresh assignment, or their current station got unassigned out from
		# under them - snap onto the first real assigned station (and its
		# real position) rather than leaving them stranded.
		current_station_id = real_ids[0]
		var station: Node2D = station_by_id.get(current_station_id)
		if station != null:
			current_position = station.position
		is_interacting = false
		return true

	if is_interacting:
		_interact_elapsed += delta
		if _interact_elapsed < INTERACT_SECONDS:
			return false
		is_interacting = false
		_interact_elapsed = 0.0
		return true

	if is_traveling:
		var target: Node2D = station_by_id.get(travel_target_station_id)
		if target == null:
			return false
		var to_target: Vector2 = target.position - current_position
		var dist := to_target.length()
		var step: float = WALK_SPEED * delta
		if dist <= step:
			current_position = target.position
			current_station_id = travel_target_station_id
			travel_target_station_id = ""
			is_traveling = false
			return true
		current_position += to_target.normalized() * step
		# Position moved but nothing UI-relevant changed - main.gd reads
		# current_position directly every frame for sprite placement, it
		# doesn't need a signal for that. Only discrete transitions (arrival,
		# interact start/end, snap) are worth telling the Shop/Station Detail
		# Menu text about - returning true every single step here would
		# rebuild those lists 60 times a second while anyone's mid-walk.
		return false

	return false


## Called by Station once it's determined there's nothing left to interact
## with here and this technician covers more than one station - starts them
## physically walking toward next_station_id (see tick() above for the
## actual movement).
func start_traveling_to(next_station_id: String) -> void:
	travel_target_station_id = next_station_id
	is_traveling = true
	current_station_id = ""


## Called by Station right after this technician actually does something -
## deposits a carried part, picks one up, or loads the active slot - a brief
## real pause representing physically handling it, during which tick() won't
## let them immediately try another action or decide to leave.
func begin_interacting() -> void:
	is_interacting = true
	_interact_elapsed = 0.0


## Chooses which of this technician's OTHER assigned stations to head to
## next, once Station._technician_act() has determined there's nothing left
## to do at the current one. Regardless of routing_strategy, delivering
## anything already being carried always comes first - there's no reason to
## walk past your own cargo's destination to go start a different machine.
## Beyond that, the two strategies genuinely disagree about what's worth
## doing next:
## - PUSH_THROUGH chases a READY station (a finished part waiting to be
##   picked up and carried onward) ahead of starting fresh work, favoring
##   getting individual Parts through the line fast.
## - MAXIMIZE_MACHINES chases a completely IDLE station with real loadable
##   work available (Station.has_actionable_work()) ahead of collecting a
##   finished part, favoring keeping as many machines running at once as
##   possible over any single Part's speed.
## Ties within a priority tier go to whichever candidate is physically
## closest - a real question now that technicians have real positions.
##
## Bug fix: this used to always return the "best" candidate even when NONE of
## them actually had anything worth doing (every candidate landing in
## _priority_tier_for()'s tier-3 fallback, "nothing special here either") -
## Station._technician_act() then unconditionally walked there anyway, and
## since arriving found the exact same "nothing to do" verdict, immediately
## turned back around next tick. With two stations and nothing productive at
## either, that's a technician stuck permanently walking back and forth
## between them, reported as "two technicians got stuck bouncing back and
## forth between 2 stations." Now returns current_station_id (i.e. "stay put,
## nowhere is actually worth walking to") whenever the best candidate is
## still only tier 3 - NOTHING_TIER below, matching _priority_tier_for()'s
## own fallback value. A technician still reacts immediately once real work
## appears somewhere, since Station._technician_act() re-evaluates every
## frame; this only stops them from wandering when there's genuinely nothing
## productive anywhere among their assigned stations.
const NOTHING_TIER: int = 3

func pick_next_station(station_by_id: Dictionary) -> String:
	var candidates: Array[String] = []
	for id in real_assigned_station_ids():
		if id != current_station_id:
			candidates.append(id)
	if candidates.is_empty():
		return current_station_id

	var best_id: String = candidates[0]
	var best_tier := 99
	var best_dist := INF
	for id in candidates:
		var station: Station = station_by_id.get(id)
		if station == null:
			continue
		var tier := _priority_tier_for(id, station)
		var dist := current_position.distance_to(station.position)
		if tier < best_tier or (tier == best_tier and dist < best_dist):
			best_id = id
			best_tier = tier
			best_dist = dist

	if best_tier >= NOTHING_TIER:
		return current_station_id
	return best_id


## Design request, this session: multiple technicians can now be assigned to
## the same station (Station.assigned_technicians, plural), but "there
## shouldn't be more than one technician working a station," and "there
## shouldn't be multiple technicians ever walking toward a station unless
## they have a reason to." Two coordination checks below implement the exact
## rules given:
##
## 1. Carrying a part bound here is ALWAYS a valid, unconditional reason to
##    go (tier 0, checked first, bypasses everything below) - "they can
##    transfer a part into the queue rack if they have one" regardless of
##    who else is working the station or headed there. Two technicians who
##    both have cargo for the same station both still walk there for exactly
##    this reason ("only the first one to get there will stay at that
##    station" - see Station._technician_act()'s active_worker claiming).
##
## 2. Without cargo, this is only a real "go do work here" reason if nobody
##    else is going to beat this technician to it: skip entirely if
##    station.active_worker already belongs to someone else (it's already
##    being handled), or if GameData.closest_assigned_technician_distance()
##    finds ANY other technician assigned here - cargo-carrying or not -
##    physically closer right now. "Whoever is closest will continue to the
##    station" covers both remaining cases this way for free: if the closer
##    other technician has cargo, IT hit tier 0 above regardless of this
##    check and is going anyway, while this (farther, cargo-less) technician
##    correctly backs off since it has no reason to race a delivery that's
##    already happening. If the closer other technician has no cargo either,
##    the comparison is a fair distance race and only the nearer one proceeds.
func _priority_tier_for(station_id: String, station: Station) -> int:
	for part in carried_parts:
		if GameData.next_station_id_for(part) == station_id:
			return 0

	if station.active_worker != null and station.active_worker != self:
		return NOTHING_TIER
	var my_distance := current_position.distance_to(station.position)
	var closest_other := GameData.closest_assigned_technician_distance(station_id, self)
	if closest_other < my_distance:
		return NOTHING_TIER

	var is_ready := station.current_state == Station.State.READY
	var is_actionable_idle := (
		station.current_state == Station.State.IDLE and station.has_actionable_work()
	)

	if routing_strategy == RoutingStrategy.PUSH_THROUGH:
		if is_ready:
			return 1
		if is_actionable_idle:
			return 2
	else: # MAXIMIZE_MACHINES
		if is_actionable_idle:
			return 1
		if is_ready:
			return 2

	return NOTHING_TIER
