extends Node

signal currency_changed(new_amount: int)
signal gems_changed(new_amount: int)
signal contract_updated(contract: Contract)
## A new rolled offer joined contract_offers, or one was removed by
## acceptance - the Contract Offers screen listens for this rather than
## polling contract_offers.size() every frame.
signal contract_offers_changed()
signal held_parts_changed()
## The nonconformance shelf gained/lost a part or a diagnosis finished.
signal nc_shelf_changed()
signal technician_updated(tech: Technician)
signal reputation_changed(new_amount: int)
## Fires whenever factory_exp changes, and again (in addition) whenever that
## pushes factory_level up - FactoryOverlay listens for this the same way
## it already listens for currency_changed, since factory progress doesn't
## otherwise correlate with any existing signal.
signal factory_progress_changed()
## Fires every payday - now specifically the wage payment bundled into every
## factory level-up (see level_up_factory()) - whether or not it was fully
## covered. StaffOverlay uses this to show a live "last payday" readout
## instead of just inferring it from currency_changed (which also fires for
## every unrelated purchase/sale).
signal payday(total_wages: int, went_into_debt: bool)

## Tier 1 numbers for every station, pulled from the design doc's
## "Starting Timer and Batch Numbers" and "Station Mechanics" sections.
## Tier 2-5 progressions aren't modeled yet, only current_tier's sprite swap is.

## THE game's timescale: how many real seconds one in-fiction minute takes.
## Every duration in the game derives from this, and nothing anywhere should
## hardcode a real-seconds duration for shop-floor time - use
## game_minutes_to_seconds() below.
##
## Set to 2.0 (a 1/30 compression of real time) as a deliberate genre decision:
## design doc Section 17's station minutes sum to 302 for one part's full
## journey, which lands a single part at ~10 real minutes end to end and a
## Tier 1 contract inside one sitting. That makes this a real-time factory sim
## you check in on, NOT the "idle first" game Section 2 and Section 14 still
## describe - those sections are now out of date and need a pass (offline
## catch-up exists and is capped deliberately, see
## SaveManager.MAX_OFFLINE_CATCHUP_SECONDS, but time away is a head start
## rather than the main way to progress).
##
## Was 1.0/3.0 (a 1/180 compression, one part in ~101 seconds) - a debug speed
## nobody could actually balance the game at, since no contract deadline,
## grace period, or wage cost had ever been observed at a playable pace.
const SECONDS_PER_GAME_MINUTE: float = 2.0

## Debug/testing override. Set from a scratch test or a future dev menu to run
## the shop at the old 180x prototype speed without re-tuning every number:
## every duration still derives from one place, so this stays honest.
static var time_scale_multiplier: float = 1.0

const MIN_TIMER_SECONDS: float = 2.0


## The single conversion from in-fiction minutes to real seconds. Station
## timers, defect grace periods, and contract deadlines all go through here, so
## changing SECONDS_PER_GAME_MINUTE rescales the whole game coherently instead
## of leaving some systems on the old scale - the exact trap the first attempt
## at this hit, where station timers slowed 6x while contract deadlines stayed
## put and every contract became instantly impossible.
##
## Deliberately NOT applied to: the contract-offer and applicant-pool refresh
## cooldowns, which are real-world pacing for how often the player is offered
## something new rather than shop-floor process time.
static func game_minutes_to_seconds(minutes: float) -> float:
	if minutes <= 0.0:
		return 0.0
	return max(minutes * SECONDS_PER_GAME_MINUTE * time_scale_multiplier, MIN_TIMER_SECONDS)

const PRINTING_SPRITES: Array[String] = [
	"res://assets/sprites/printing_station_L1.png",
	"res://assets/sprites/printing_station_L2.png",
	"res://assets/sprites/printing_station_L3.png",
	"res://assets/sprites/printing_station_L4.png",
	"res://assets/sprites/printing_station_L5.png",
]

## No tiered art yet, per the design brief: reuse the one sprite at every tier.
const BURNOUT_SPRITES: Array[String] = [
	"res://assets/sprites/burnout_furnace.png",
	"res://assets/sprites/burnout_furnace.png",
	"res://assets/sprites/burnout_furnace.png",
	"res://assets/sprites/burnout_furnace.png",
	"res://assets/sprites/burnout_furnace.png",
]
const POUR_SPRITES: Array[String] = [
	"res://assets/sprites/pour_station.png",
	"res://assets/sprites/pour_station.png",
	"res://assets/sprites/pour_station.png",
	"res://assets/sprites/pour_station.png",
	"res://assets/sprites/pour_station.png",
]

## Real 3-state art for Clean (design request, this session), the first
## station with genuine per-state photos instead of a generic tinted
## placeholder box - index 0 = idle (closed), 1 = running (open, basket
## submerged), 2 = ready (open, basket lifted out). Passed as a
## StationDef's `state_sprites` constructor arg, NOT `tier_sprites` above -
## Station.state_sprites is indexed by current_state, not current_tier, and
## Clean has no tiered art of its own.
const CLEAN_STATE_SPRITES: Array[String] = [
	"res://assets/sprites/cleaner_1.png",
	"res://assets/sprites/cleaner_2.png",
	"res://assets/sprites/cleaner_3.png",
]
## Bug fix (design feedback: "the cleaner is a bit larger than the rest") -
## cleaner_1/2/3.png are 1254x1254, the same resolution class as Burnout/
## Pour's real art, which reads fine for them since each gets a whole room
## mostly to itself - Clean instead sits packed into a tight row with UV
## Cure/Scan/Patching's small placeholder boxes, where the same on-screen
## size as Burnout/Pour visibly dwarfed its neighbors. Shrinks it down to
## roughly match Printing's own real-art on-screen size instead.
const CLEAN_SPRITE_SCALE_OVERRIDE: float = 0.35


## Design doc Section 9: Quality, Defects, and Geometry Familiarity. Covers a
## defect happening, getting flagged, escalating if ignored, and now (this
## pass) the three fix paths that actually clear a flagged defect - mortar
## patch (mortar_patch_defect(), Shell Crack only, doesn't raise
## familiarity), redesign (redesign_defect(), any category, raises
## familiarity), and a resolved specialist visit (hire_specialist() auto-
## resolves every currently-flagged Part in its categories, also raises
## familiarity) - plus Push Through (Station._resolve_push_through(), Pour
## only, a bigger familiarity jump win or lose, but a loss destroys the part
## outright rather than just flagging it).
enum DefectCategory { NONE, SHELL_CRACK, WARPING, POROSITY, MISRUN, INCLUSION }

const DEFECT_CATEGORY_LABEL := {
	DefectCategory.NONE: "",
	DefectCategory.SHELL_CRACK: "Shell Crack",
	DefectCategory.WARPING: "Warping",
	DefectCategory.POROSITY: "Porosity",
	DefectCategory.MISRUN: "Misrun",
	DefectCategory.INCLUSION: "Inclusion",
}

## Base risk, revised this session per design doc Section 21.6: "defect
## sources are now exactly four: Printing, Shelling, Burnout, Pour." Deshell
## and Abrasive Blast (which briefly had risk numbers) are purely mechanical
## now, no defect risk at all - see STATION_BASE_DEFECT_RISK below, which no
## longer has entries for them. Every other station (Clean, UV Cure, Scan,
## Patching, Pour Cup Attach, Mold Prep, Ship) never rolls a defect at all,
## discards it on arrival.
## "grinding" added this session (design request: "i want to add grinding to
## the post process room. grinding can cause a defect") - a first-pass
## placeholder risk between Printing's and Burnout's.
const STATION_BASE_DEFECT_RISK := {
	"printing": 0.05,
	"shelling": 0.20,
	"burnout": 0.15,
	"pour": 0.20,
	"grinding": 0.12,
}

## Design doc Section 21.6: "Push Through is generalized beyond Pour... it now
## applies conceptually to any part moving through the pipeline with a known
## defect" - specifically the four stations 21.6 lists familiarity effects
## for. Printing is deliberately excluded: "Printing-sourced defects
## specifically never reach a player decision point at all, they flow
## straight through Scan into Patching's auto-resolve."
const PUSH_THROUGH_ELIGIBLE_STATIONS: Array[String] = ["shelling", "burnout", "mold_prep", "pour"]

## Which defect category a station rolls when it does flag one, per Section
## 9's "Likely Defect" column. Burnout and Pour each list two candidates -
## split evenly (see roll_defect_category() below), since the doc gives no
## relative weighting between them to justify anything else. Deshell and
## Abrasive Blast are gone from here per Section 21.6 - see
## STATION_BASE_DEFECT_RISK's comment above.
## "grinding" (this session) is the first and only station to roll
## INCLUSION - a category that's existed in the enum since before this
## session but no station ever actually rolled it (Deshell/Abrasive Blast,
## its only past sources, lost their defect risk entirely per the comment
## above). Note there's no Specialist covering Inclusion (see
## SPECIALIST_CATEGORIES below) - a known, pre-existing gap, not new.
const STATION_DEFECT_CATEGORIES := {
	"printing": [DefectCategory.WARPING],
	"shelling": [DefectCategory.SHELL_CRACK],
	"burnout": [DefectCategory.WARPING, DefectCategory.SHELL_CRACK],
	"pour": [DefectCategory.POROSITY, DefectCategory.MISRUN],
	"grinding": [DefectCategory.INCLUSION],
}

## Real minutes from Section 9's grace period table, converted to
## prototype-scale seconds the same way Station timers are (see
## get_prototype_timer_seconds() below) - grace_period_seconds_for() applies
## that conversion. Includes every station the doc lists even though only
## the six above ever actually flag a defect right now; harmless to have the
## rest on hand already.
const STATION_GRACE_PERIOD_MINUTES := {
	"printing": 30.0, "scan": 30.0, "uv_cure": 30.0,
	"pour_cup_attach": 30.0, "deshell": 30.0, "abrasive_blast": 30.0,
	"burnout": 40.0,
	"shelling": 45.0,
	"pour": 20.0,
	"grinding": 25.0,
}

## Familiarity star (0-5) -> risk multiplier, Section 9's table. 5 stars
## floors at 10%, never zero - "genuinely risky early, genuinely safe once
## mastered."
const FAMILIARITY_MULTIPLIER: Array[float] = [1.0, 0.8, 0.6, 0.4, 0.2, 0.1]


## Design doc Section 21.7: familiarity is no longer a single score - "a part
## builds up to four separate familiarity values for its geometry, one each
## for Shelling, Burnout, Mold Prep, and Pour, since those are genuinely
## different skills to develop." Printing is deliberately NOT tracked here -
## printer defects always auto-resolve for free at Patching (Section 21.4),
## so there's no risk there for familiarity to meaningfully reduce.
const FAMILIARITY_TRACKED_STATIONS: Array[String] = ["shelling", "burnout", "mold_prep", "pour"]

## A geometry name (a flavor string for now, resolved per-Part via
## GameData.geometry_name_for_part() since Section 24.1 - the real geometry
## family system from Section 10 isn't built yet) -> {station_id: stars 0-5}, one
## entry per FAMILIARITY_TRACKED_STATIONS station. A geometry/station pair
## never seen is 0 stars, brand new. Raised only by raise_familiarity()
## below, called from a redesign, a resolved specialist visit, or a Push
## Through attempt (win or lose) - never by a plain successful run, matching
## Section 9's "Redesign fixes, resolved specialist visits, and push through
## attempts all raise it" - now scoped to whichever specific station the
## defect/push-through actually happened at, not a blanket score.
var geometry_familiarity: Dictionary = {}

## Per-station production stats for the Factory screen (design doc 27.3/
## 27.4: cycle time, yield and throughput, to make informed upgrades).
## station_id -> {"completed": runs finished, "flagged": runs that flagged a
## new defect here, "cycle_total": summed real seconds of those runs, "busy":
## real seconds spent running}. stats_elapsed is the shared clock busy time
## is measured against. All advanced from simulate() (via
## Station.simulate_step()), so offline catch-up counts too, and saved.
## Cumulative since the save began - no rolling window yet.
var station_stats: Dictionary = {}
var stats_elapsed: float = 0.0

## First-pass placeholder currency costs for the two per-Part fix paths
## (Section 9). The doc gives no concrete numbers, only that a mortar patch
## is "quick, cheap, and reliable" and a redesign spends real "time and
## money" - same spirit as every other placeholder cost in this file.
const MORTAR_PATCH_COST: int = 40
const REDESIGN_COST: int = 150

## How many familiarity stars each fix path grants, capped by raise_familiarity()
## at 5. A mortar patch grants none at all - see mortar_patch_defect()'s own
## comment for why. Push Through's jump is deliberately bigger than a normal
## fix's, per Section 9: "a push through always grants a bigger familiarity
## jump than a normal completed part would... since deliberately testing
## teaches you faster than just running the safe route."
const FAMILIARITY_GAIN_REDESIGN: int = 1
const FAMILIARITY_GAIN_SPECIALIST: int = 1
const FAMILIARITY_GAIN_PUSH_THROUGH: int = 2

## Section 9's third fix path: "a hire distinct from station technicians,
## tied to a defect category rather than a station." Each type is a one-time
## permanent hire (no ongoing wage, unlike a station Technician - the doc
## never mentions one) rather than something assigned anywhere.
## SPECIALIST_CATEGORIES is which DefectCategory values each type covers,
## straight from Section 9's table - Inclusion has no matching specialist at
## all, the doc only lists three.
enum SpecialistType { SHELL, POUR, PATTERN }

const SPECIALIST_LABEL := {
	SpecialistType.SHELL: "Shell Specialist",
	SpecialistType.POUR: "Pour Specialist",
	SpecialistType.PATTERN: "Pattern Specialist",
}
const SPECIALIST_CATEGORIES := {
	SpecialistType.SHELL: [DefectCategory.SHELL_CRACK],
	SpecialistType.POUR: [DefectCategory.POROSITY, DefectCategory.MISRUN],
	SpecialistType.PATTERN: [DefectCategory.WARPING],
}
## First-pass placeholder, same spirit as Technician.TIER_HIRE_COST - priced
## near a Master technician's 900g since Section 9 calls the effect "a big
## permanent reduction," a major shopwide investment rather than a small buy.
const SPECIALIST_HIRE_COST: int = 650

## Section 9's worked example multiplies this in directly as "50%" - applied
## as a post-roll suppression chance in Station._roll_defect_outcome() rather
## than folded into the base risk multiply, since a station like Burnout
## rolls between two categories covered by two DIFFERENT specialists (Warping
## -> Pattern, Shell Crack -> Shell) and the category isn't known until after
## the base risk roll already hit.
const SPECIALIST_RISK_MULTIPLIER: float = 0.5

## Which SpecialistType values have actually been hired - see hire_specialist().
var specialists_hired: Array[SpecialistType] = []


class StationDef:
	var id: String
	var display_name: String
	var station_type: Station.StationType
	var phase: int
	var room_name: String
	var tier1_timer_minutes: float
	var tier1_batch_cap: int
	var tier_sprite_paths: Array[String]
	## Real per-state art (idle/running/ready), distinct from tier_sprite_paths
	## above - see Station.state_sprites and CLEAN_STATE_SPRITES.
	var state_sprite_paths: Array[String]
	## See Station.sprite_scale_override's own comment - a fudge factor for a
	## real art asset whose native resolution doesn't match what most station
	## art assumes. 1.0 (no change) unless a station specifically needs it.
	var sprite_scale_override: float = 1.0

	func _init(
		p_id: String,
		p_name: String,
		p_type: Station.StationType,
		p_phase: int,
		p_room: String,
		p_minutes: float,
		p_batch: int,
		p_sprites: Array[String] = [],
		p_state_sprites: Array[String] = [],
		p_sprite_scale_override: float = 1.0
	) -> void:
		id = p_id
		display_name = p_name
		station_type = p_type
		phase = p_phase
		room_name = p_room
		tier1_timer_minutes = p_minutes
		tier1_batch_cap = p_batch
		tier_sprite_paths = p_sprites
		state_sprite_paths = p_state_sprites
		sprite_scale_override = p_sprite_scale_override

	## Prototype-scale seconds derived from the real Tier 1 minutes above.
	func get_prototype_timer_seconds() -> float:
		if tier1_timer_minutes <= 0.0:
			return 0.0
		return GameData.game_minutes_to_seconds(tier1_timer_minutes)


## Placeholder economy: no alloy stock or contract payouts yet, just a
## simple number so hiring has something to spend. Real economy later.
var currency: int = 500

## Second, "harder to get" currency (design request, this session: "there
## will be an additional type of currency like the diamond that are harder
## to get and will be used to finish upgrades, fill in for normal currency
## if you dont have enough for a purchase") - a real first-pass build, not
## just a documented idea. Earned far more sparingly than currency: the only
## source right now is a small reward on every Factory Level gain (see
## _award_factory_exp()) - a genuine milestone, not routine contract income.
var gems: int = 0

## First-pass placeholder exchange rate for "filling in" a currency
## shortfall - 1 gem covers this much missing gold. No basis in the doc
## since the mechanic didn't exist before this session; picked to sit
## comfortably below the cheapest real purchases (a Tier 2 station upgrade)
## so a small shortfall doesn't demand a huge gem spend.
const GEM_TO_CURRENCY_VALUE: int = 50

## First-pass placeholder reward per Factory Level gained.
const FACTORY_LEVEL_UP_GEM_REWARD: int = 5

var stations: Array[StationDef] = []
var contracts: Array[Contract] = []

## Rolled contracts the player hasn't accepted yet (design doc Section 24.9 /
## the "Contract Offers" screen) - a genuinely separate pool from `contracts`
## above. An offer's deadline clock is NOT running (Contract.start() isn't
## called until accept_contract_offer() below) and it doesn't count toward
## anything work-related (get_active_contracts(), count_parts_in_pipeline(),
## the backpressure/auto-queue logic) until the player actually accepts it.
## The six starting contracts skip this pool entirely and go straight into
## `contracts` already-active, so a brand new player isn't handed an extra
## "accept your own starting work" step - only contracts generated afterward
## via generate_contract() ever appear here.
var contract_offers: Array[Contract] = []

## The pipeline in real production sequence, revised this session per design
## doc Section 21.3-21.5: Deplate is gone entirely (collecting a finished
## pattern off a printer *is* the deplate action, no separate station or
## timer - see the printer rework below), and Clean/Patching/Mold Prep are
## new. Order matters here for two different reasons at once: it's the
## literal sequence Station.next_station links get wired in (main.gd), AND
## Part.current_station_index is an index into this array (see
## next_station_id_for() below) - incremented once per station a Part
## actually visits. "printing" at index 0 is a bit special post-21.2: it's no
## longer one real Station id (there can be several purchased printer
## instances, ids "printing_1"/"printing_2"/...), but every Part still starts
## life with current_station_index = 0 regardless of which printer instance
## created it, so PIPELINE_ORDER[1] ("clean") is still exactly right as
## "whatever comes after printing" no matter which physical printer a given
## Part came off of. Nothing ever looks "printing" up directly in
## station_by_id for routing purposes - see GameData.printer_station_ids for
## the real per-instance ids, and Station._try_send_to_next_station()/
## next_station for how a printer instance's own outgoing link is wired.
## "grinding" inserted this session between Deshell and Abrasive Blast -
## matches the real investment-casting order (shell removal -> grind off
## gates/sprues -> final surface blast -> ship).
const PIPELINE_ORDER: Array[String] = [
	"printing", "clean", "uv_cure", "scan", "patching", "pour_cup_attach",
	"shelling", "burnout", "mold_prep", "pour", "deshell", "grinding", "abrasive_blast", "ship",
]

## Every Part currently alive anywhere in the shop (in a station or held),
## from creation until it ships. Backs the Contracts menu tab's "quantity
## currently in the pipeline" column - see count_parts_in_pipeline().
var active_parts: Array[Part] = []

## Parts manually Collected off an unstaffed station, waiting on a player
## decision for where they go next (design doc Section 6, Awaiting Transfer).
## Staffed stations route parts themselves and never touch this list.
var held_parts: Array[Part] = []

## Every technician ever hired, whether or not they're currently assigned
## anywhere - the Shop's Technicians tab roster (design doc Section 6/7).
var technicians: Array[Technician] = []

## Wage economy (design doc Section 6/7's wage numbers existed on Technician
## from the start, but nothing ever spent them - see Technician.wage).
## Design request, this session: "have wages be an addition to the factory
## level" - payday is no longer a standing real-time clock (that first-pass
## version is gone); wages are now paid out as part of leveling up the
## factory itself (see level_up_factory() below), a deliberate, escalating
## milestone cost instead of ambient background drain. total_wage_payroll()
## stays a standalone query - it's also what the Printers overlay previews
## before the player commits to a level-up, and what StaffOverlay shows as
## the roster's current standing cost.
func total_wage_payroll() -> int:
	var total := 0
	for tech in technicians:
		total += tech.wage
	return total


func is_in_wage_debt() -> bool:
	return currency < 0


## Rotating applicant pool (design request, this session: "build the rotating
## applicant pool" - replacing "hire any tier, any time"), mirroring the
## contract_offers pattern exactly: a pool of rolled-but-unhired candidates,
## separate from technicians (the real roster) - hire_applicant() below is
## what actually moves one over.
var applicant_pool: Array[Technician] = []
signal applicant_pool_changed()

const APPLICANT_POOL_SIZE: int = 4
## First-pass placeholder, same spirit as every other invented number in
## this file - much longer than CONTRACT_GENERATION_COOLDOWN_SECONDS (45s)
## since staff hiring is meant to feel like a slower, more deliberate cadence
## than the standing contract pool.
const APPLICANT_POOL_REFRESH_COOLDOWN_SECONDS: float = 300.0
## Gems only, not try_spend_with_gems()'s gold-first-then-gems fallback -
## "refreshable for gems" specifically means this action costs the harder-to-
## get currency, not a small amount of ordinary gold that happens to get
## covered by ready cash. First-pass placeholder, priced well under
## FACTORY_LEVEL_UP_GEM_REWARD's own per-level payout so it's a real but not
## crushing spend.
const APPLICANT_REFRESH_COST: int = 3

const APPLICANT_FIRST_NAMES: Array[String] = [
	"Daniel", "Maya", "Jakob", "Victor", "Elena", "Marcus", "Priya", "Owen", "Sofia", "Derek",
]
const APPLICANT_LAST_NAMES: Array[String] = [
	"Price", "Singh", "Klein", "Moreau", "Reyes", "Chen", "Novak", "Brooks", "Ibarra", "Walsh",
]

## Weighted toward lower tiers, same shape/spirit as CONTRACT_TIER_ROLL_WEIGHTS -
## a standing pool of mostly-Apprentice/Technician candidates with an
## occasional Senior/Master, not an even spread.
const APPLICANT_TIER_ROLL_WEIGHTS: Array[int] = [40, 30, 20, 10]

var _applicant_pool_cooldown: float = 0.0


func _roll_applicant_tier() -> Technician.SkillTier:
	var tiers := Technician.SkillTier.values()
	var total := 0
	for w in APPLICANT_TIER_ROLL_WEIGHTS:
		total += w
	var roll := randf() * total
	for i in tiers.size():
		roll -= APPLICANT_TIER_ROLL_WEIGHTS[i]
		if roll <= 0.0:
			return tiers[i]
	return tiers[0]


## A brand new, unhired candidate - random role, tier, name, and (via
## Technician.roll_department_skills()) per-department skill. Never appended
## to applicant_pool itself here - callers decide where it goes.
func generate_applicant() -> Technician:
	var applicant := Technician.new()
	applicant.role = Technician.StaffRole.TECHNICIAN if randf() < 0.5 else Technician.StaffRole.ENGINEER
	applicant.skill_tier = _roll_applicant_tier()
	applicant.technician_name = "%s %s" % [
		APPLICANT_FIRST_NAMES[randi() % APPLICANT_FIRST_NAMES.size()],
		APPLICANT_LAST_NAMES[randi() % APPLICANT_LAST_NAMES.size()],
	]
	applicant.roll_department_skills()
	return applicant


func can_afford_applicant_refresh() -> bool:
	return gems >= APPLICANT_REFRESH_COST


## The paid "Refresh Applicants" button - a full reroll of the whole pool,
## distinct from the passive auto-refill below (which only ever tops up
## slots emptied by a hire, never discards a candidate you might still be
## saving up for).
func refresh_applicant_pool() -> bool:
	if not can_afford_applicant_refresh():
		return false
	gems -= APPLICANT_REFRESH_COST
	gems_changed.emit(gems)
	applicant_pool.clear()
	for i in APPLICANT_POOL_SIZE:
		applicant_pool.append(generate_applicant())
	_applicant_pool_cooldown = APPLICANT_POOL_REFRESH_COOLDOWN_SECONDS
	applicant_pool_changed.emit()
	return true


## Free, passive top-up - only ever fills slots the pool is actually missing
## (from a hire, or the very first time at startup), never replaces a
## candidate still sitting there unhired.
func _refill_applicant_pool() -> void:
	var changed := false
	while applicant_pool.size() < APPLICANT_POOL_SIZE:
		applicant_pool.append(generate_applicant())
		changed = true
	if changed:
		applicant_pool_changed.emit()


func _process_applicant_pool(delta: float) -> void:
	_applicant_pool_cooldown = max(_applicant_pool_cooldown - delta, 0.0)
	if _applicant_pool_cooldown <= 0.0:
		_refill_applicant_pool()
		_applicant_pool_cooldown = APPLICANT_POOL_REFRESH_COOLDOWN_SECONDS


## Read-only window onto _applicant_pool_cooldown for the Staff overlay's
## countdown display, so that var can stay private rather than the UI
## reaching into GameData's own internal state directly.
func applicant_pool_refresh_seconds_left() -> float:
	return _applicant_pool_cooldown


## Moves an applicant from the pool into the real roster, spending their
## hire_cost the same gold-first-then-gems way every other purchase in the
## game works (unlike the pool refresh above, ordinary hiring isn't meant to
## be a gems-only action).
func hire_applicant(applicant: Technician) -> bool:
	if not applicant_pool.has(applicant):
		return false
	if not try_spend_with_gems(applicant.hire_cost):
		return false
	applicant_pool.erase(applicant)
	technicians.append(applicant)
	applicant_pool_changed.emit()
	return true

## station_id -> live Station node, set by main.gd right after spawning all
## 11 stations (same pattern as every overlay's own station_by_id).
## Technician.tick() needs this to look up real station positions for actual
## distance-based walking - see Technician.walk_speed().
var station_by_id: Dictionary = {}


## First-pass placeholder costs for raising a station's current_tier, same
## spirit as the Technician hire costs - Section 17 only says each tier
## should cost roughly 1.5-2x the previous one, no concrete numbers given.
## Index = tier being upgraded TO; index 0-1 unused since Tier 1 is the free starting tier.
const STATION_TIER_UPGRADE_COST: Array[int] = [0, 0, 100, 175, 300, 500]

## Design doc Section 21.1: rack capacity is now its own purchase, entirely
## separate from current_tier - see Station.rack_capacity/try_upgrade_rack().
## The doc gives no concrete numbers (same as every other placeholder cost
## table here) - a flat-ish early curve since even one extra rack slot is a
## real, immediately useful buy, steepening toward Station.MAX_RACK_CAPACITY
## (10, a hard UI limit - see StationDetailMenu's fixed rack grid). Index =
## rack_capacity being upgraded TO; index 0-1 unused, Tier/rack level 1 is free.
const STATION_RACK_UPGRADE_COST: Array[int] = [
	0, 0, 30, 45, 65, 90, 120, 160, 210, 270, 340,
]

## Design doc Section 21.2: "tier upgrades on a given printer eventually
## unlock batched print jobs on that printer." No concrete tier thresholds
## given - first-pass placeholder, same spirit as every other invented
## number in this file: unbatched through Tier 2, batching unlocks Tier 3+.
## Applied by Station._apply_tier_batch_effects() to any station_id starting
## with "printing" (see the multi-printer rework, GameData.buy_printer()).
const PRINTER_TIER_BATCH_CAP := {1: 1, 2: 1, 3: 2, 4: 3, 5: 4}

## Design doc Section 4 (revised this session): "single part at Tier 1;
## batched at Tier 2+." No concrete numbers given - first-pass placeholder,
## loosely following the old Section 17 Tier 1->5 batch progression's shape
## without being bound to its now-superseded absolute numbers.
const ABRASIVE_BLAST_TIER_BATCH_CAP := {1: 1, 2: 3, 3: 4, 4: 5, 5: 6}

## Design doc Section 4/21.4: "Shelling: single part at Tier 1; parallel
## independent timers at Tier 2+." Station.batch_cap is repurposed for
## Shelling specifically as "how many parts can run their own independent
## timer at once" rather than a shared-batch-timer size - see
## Station.uses_parallel_runs()/shelling_active_parts. No concrete tier
## thresholds given - first-pass placeholder, one extra parallel slot per tier
## starting at Tier 2.
const SHELLING_TIER_PARALLEL_CAP := {1: 1, 2: 2, 3: 3, 4: 4, 5: 5}
## Batch stations (user request, 2026-10-03): Burnout, Clean and UV Cure
## run a whole load per cycle. A part put in waits, loaded, and its timer
## only starts when the technician starts the next cycle - unlike Shelling,
## where each part starts its own timer the moment it goes in. Load size by
## tier, placeholder numbers.
const BATCH_TIER_LOAD_CAP := {
	"burnout": {1: 4, 2: 6, 3: 8, 4: 10, 5: 12},
	"clean": {1: 4, 2: 5, 3: 6, 4: 8, 5: 10},
	"uv_cure": {1: 4, 2: 6, 3: 8, 4: 10, 5: 12},
}
## A technician holding a part-full load starts the cycle once it's waited
## this long for more parts (or right away if it's full or nothing more is
## coming). Unstaffed, only the player starts a cycle.
const BATCH_FILL_WAIT_GAME_MINUTES: float = 15.0


## Design doc Section 8: Contracts (reputation, randomized generation, repeat
## clients, per-company relationships). Previously the six starting contracts
## were the whole pool and Reputation was purely a stub referenced from
## Station._ship_part()'s escalation comment - this section makes both real.
## Shop-wide Reputation, 0-100, starting at 0 to match Section 1's framing:
## the company already knows the process, but has never run it at real
## commercial volume for outside customers, so trust with the outside world
## starts from nothing regardless of in-house skill.
const REPUTATION_MAX: int = 100
var reputation: int = 0

## First-pass placeholder deltas, same spirit as every other invented number
## in this file - Section 8 only says finishing on time with a low defect
## rate raises Reputation, missing deadlines or shipping too many defective
## parts lowers it, no concrete numbers given.
const REPUTATION_GAIN_ON_TIME_COMPLETE: int = 8
const REPUTATION_LOSS_MISSED_DEADLINE: int = 10
const REPUTATION_LOSS_DEFECTIVE_SHIP: int = 2

## Section 8: "Reputation threshold, a few Tier 1s completed" / "higher
## reputation, solid Tier 2 track record" / "high reputation, several strong
## Tier 3 completions" - qualitative only, first-pass numbers here.
const REPUTATION_TIER_THRESHOLD := {
	Contract.ContractTier.LOCAL_SHOPS: 0,
	Contract.ContractTier.REGIONAL_MANUFACTURERS: 15,
	Contract.ContractTier.INDUSTRIAL_ACCOUNTS: 40,
	Contract.ContractTier.FLAGSHIP: 75,
}

## Section 8's "Per-Company Relationship, separate from shop-wide
## Reputation: a 0 to 5 star score per company." customer_name -> stars,
## same 0..N-not-yet-seen-is-zero pattern as geometry_familiarity.
var company_relationships: Dictionary = {}
const RELATIONSHIP_GAIN_ON_TIME_COMPLETE: float = 1.0
const RELATIONSHIP_LOSS_MISSED_DEADLINE: float = 1.5
const RELATIONSHIP_LOSS_DEFECTIVE_SHIP: float = 0.5

## Section 8: "there's a base chance (roughly 20% to start) it pulls a
## company already worked with instead of generating a brand new name, and
## that chance rises the better relationships are going overall." Scaled
## linearly by the average of every known relationship (0..5 stars), capped
## at REPEAT_CLIENT_MAX_CHANCE - first-pass shape, the doc gives no formula.
const REPEAT_CLIENT_BASE_CHANCE: float = 0.20
const REPEAT_CLIENT_MAX_CHANCE: float = 0.55
## Section 8: "at 5 stars a chance they offer something a tier above what
## general Reputation would normally unlock."
const REPEAT_CLIENT_TIER_BUMP_RELATIONSHIP_STARS: float = 5.0
const REPEAT_CLIENT_TIER_BUMP_CHANCE: float = 0.30

## Design request (this session): "the higher your company reputation the
## better contracts you'll get from current companies you work with as well
## as attract contracts from other bigger companies with better contracts."
## A continuous bonus on top of Reputation's existing tier-gating
## (REPUTATION_TIER_THRESHOLD) - every generated contract's quantity and
## payout scale up by as much as this fraction as Reputation climbs from 0
## to REPUTATION_MAX, so Reputation keeps improving contract terms smoothly
## between tier thresholds too, not just at the moment one clears. Applies
## equally to repeat clients and brand new ones - see generate_contract().
const REPUTATION_QUALITY_BONUS_MAX: float = 0.35

## How many currently-active (not yet complete) contracts the offered pool
## tries to stay topped up to, and the minimum real-time gap between two
## generated offers landing back to back. Section 8 doesn't specify a
## trigger mechanism for new contract generation at all - this is a
## first-pass placeholder interpretation: keep a small standing pool of
## real jobs available rather than a single-contract-at-a-time queue,
## consistent with Section 8's "multiple contracts run at once" / overlap
## structure. Checked from _process_contracts() below.
## Renamed in spirit this session: this now floors the size of the
## *offers* pool (contract_offers), not the active/accepted one - filling
## the active pool is now an explicit player action (accept_contract_offer()),
## not automatic. Generation still only fires while below this floor, so the
## pool settles at roughly this size and only grows a fresh offer once an
## existing one gets accepted (freeing a slot) - see _process_contracts().
const MIN_ACTIVE_CONTRACTS: int = 4
const CONTRACT_GENERATION_COOLDOWN_SECONDS: float = 45.0
var _contract_generation_cooldown: float = 0.0

## How many line items a generated offer asks for, by tier - bigger/later-
## tier customers ask for more variety at once (design doc Section 24.1: "A
## customer contract can have multiple parts that they're asking for").
## First-pass placeholder shape, same spirit as every other invented number
## in this file.
const LINE_ITEM_COUNT_RANGE := {
	Contract.ContractTier.LOCAL_SHOPS: Vector2i(1, 1),
	Contract.ContractTier.REGIONAL_MANUFACTURERS: Vector2i(1, 2),
	Contract.ContractTier.INDUSTRIAL_ACCOUNTS: Vector2i(2, 3),
	Contract.ContractTier.FLAGSHIP: Vector2i(2, 4),
}

## Section 8: "company names and the part/alloy work they need are two fully
## separate pools, rolled independently rather than fixed pairs." Company
## pools transcribed from Section 10's "Aerospace Contract Pool" lists
## (small independents / mid-size suppliers / flagship primes), keyed by the
## contract tier they're offered at. Tier 2 and Tier 3 intentionally share
## one pool, matching Section 10's own "(Tier 2 to 3)" tagging for the
## mid-size supplier list - tier itself (quantity/deadline/payout) is what
## actually differs, not which companies can appear.
const COMPANY_POOL := {
	Contract.ContractTier.LOCAL_SHOPS: [
		"Ironwing Fabrication", "Truenorth Precision", "Sparrowhawk Tooling",
		"Redline Machine Works", "Halcyon Components",
	],
	Contract.ContractTier.REGIONAL_MANUFACTURERS: [
		"Vantage Aerostructures", "Solstice Precision Manufacturing",
		"Ferrolux Industrial", "Apex Airframe Supply", "Cascade Turbomachinery",
	],
	Contract.ContractTier.INDUSTRIAL_ACCOUNTS: [
		"Vantage Aerostructures", "Solstice Precision Manufacturing",
		"Ferrolux Industrial", "Apex Airframe Supply", "Cascade Turbomachinery",
	],
	Contract.ContractTier.FLAGSHIP: [
		"Altair Aerospace & Defense", "Zenith Dynamics", "Constellation Aerosystems",
		"Ironclad Aerostructures", "Skyforge Industries", "Pinnacle Aeroworks",
	],
}

## Section 10's geometry families, minus the ones already fully used up by
## the six starting contracts (Bracket/Decorative/Valve/Housing all still
## reappear here too - Section 8 explicitly wants a company able to come
## back needing something completely different, not a one-geometry-per-
## family cap). FAMILY_MIN_TIER loosely follows Section 10's complexity
## column (Low->1, Medium->2, High/"similar to Impeller"->3, Very High->4) -
## first-pass placeholder mapping, the doc ties complexity to fixes-to-master
## rather than to contract tier directly.
const FAMILY_MIN_TIER := {
	"Decorative": Contract.ContractTier.LOCAL_SHOPS,
	"Bracket": Contract.ContractTier.LOCAL_SHOPS,
	"Valve": Contract.ContractTier.REGIONAL_MANUFACTURERS,
	"Housing": Contract.ContractTier.REGIONAL_MANUFACTURERS,
	"Seal": Contract.ContractTier.REGIONAL_MANUFACTURERS,
	"Impeller": Contract.ContractTier.INDUSTRIAL_ACCOUNTS,
	"Manifold": Contract.ContractTier.INDUSTRIAL_ACCOUNTS,
	"Strut": Contract.ContractTier.INDUSTRIAL_ACCOUNTS,
	# Turbine/HotSection lowered from FLAGSHIP-only to INDUSTRIAL_ACCOUNTS this
	# session (design doc Section 24.3, "a much larger, visually distinct real
	# geometry roster... so it doesn't feel like you're continuously
	# processing the same parts over and over again") - gating the whole
	# aerospace-signature rotating/hot-section geometries behind the rarest
	# tier meant they almost never showed up. Flagship-tier work in these
	# families still exists (bigger quantities, pricier alloys), it's just no
	# longer the ONLY tier that can roll them.
	"Turbine": Contract.ContractTier.INDUSTRIAL_ACCOUNTS,
	"HotSection": Contract.ContractTier.INDUSTRIAL_ACCOUNTS,
}
## Section 10's per-family Complexity column (Low/Medium/High/Very High),
## surfaced directly on the new Contract Offers screen's difficulty tag
## (design doc Section 24.8 flags a future per-geometry number as a richer
## follow-up - this is the simpler per-family version that already existed
## in the design doc, just not displayed anywhere in-game until now).
const FAMILY_COMPLEXITY_LABEL := {
	"Decorative": "Low", "Bracket": "Low",
	"Valve": "Medium", "Housing": "Medium", "Seal": "Medium",
	"Impeller": "High", "Manifold": "High", "Strut": "High",
	"Turbine": "Very High", "HotSection": "Very High",
}
const GEOMETRY_POOL := {
	"Decorative": ["Pendant Blanks", "Decorative Medallions"],
	"Bracket": ["Mounting Brackets", "Engine Mount Brackets", "Avionics Mounting Brackets", "Actuator Support Brackets"],
	"Valve": ["Valve Bodies", "Valve Handles", "Bleed Air Valve Bodies", "Fuel Shutoff Valve Bodies"],
	"Housing": ["Pump Housings", "Gear Housings", "Bearing Housings", "Sensor Housings", "Actuator Housings"],
	"Seal": ["Seal Rings", "Diffuser Rings"],
	"Impeller": ["Pump Impellers", "Blower Impellers", "Compressor Impellers", "Fuel Pump Impellers"],
	"Manifold": ["Hydraulic Manifolds", "Fuel Manifolds", "Bleed Air Manifolds"],
	"Strut": ["Landing Gear Struts", "Actuator Linkages"],
	# Expanded this session (design doc Section 24.3, direct request: "blades,
	# turbines, blisks, recuperators, hot case sections... veins" [vanes]) -
	# Turbine Blades/Vanes already existed; Blisks, Nozzle Guide Vanes, and
	# Compressor Vanes are new rotating-hardware geometries in the same family.
	"Turbine": ["Turbine Blades", "Turbine Vanes", "Nozzle Guide Vanes", "Compressor Vanes", "Blisks"],
	# New family this session - the hot-section/casing side of the same
	# aerospace ask, distinct from Turbine's rotating hardware.
	"HotSection": ["Combustor Liners", "Recuperators", "Hot Section Casings"],
}

## Section 10's alloy table, "roughly matched to contract tier."
const ALLOY_POOL := {
	Contract.ContractTier.LOCAL_SHOPS: ["Bronze", "Mild Steel", "Aluminum Alloy"],
	Contract.ContractTier.REGIONAL_MANUFACTURERS: ["Cast Iron Blend", "Stainless Steel", "Aluminum Alloy", "Titanium Alloy"],
	Contract.ContractTier.INDUSTRIAL_ACCOUNTS: ["Alloy Steel", "Titanium Alloy", "Maraging Steel", "Stainless Steel, PH Grade"],
	Contract.ContractTier.FLAGSHIP: ["Nickel Superalloy", "Cobalt-Based Superalloy", "Maraging Steel"],
}

## Section 8's tier table ("3 to 8 parts" / "10 to 25" / "25 to 75" / "75+"),
## the deadline constants matching the six hand-authored starting contracts'
## own per-tier values exactly (so a generated Tier 1 contract feels the same
## as Local Hardware Co.'s), and a per-unit payout rate derived from those
## same six contracts' own payout/quantity ratios, jittered +/-15% per
## generated contract for variety.
const CONTRACT_QUANTITY_RANGE := {
	Contract.ContractTier.LOCAL_SHOPS: Vector2i(3, 8),
	Contract.ContractTier.REGIONAL_MANUFACTURERS: Vector2i(10, 25),
	Contract.ContractTier.INDUSTRIAL_ACCOUNTS: Vector2i(25, 75),
	Contract.ContractTier.FLAGSHIP: Vector2i(75, 150),
}
## In GAME MINUTES, converted through game_minutes_to_seconds() at use, so a
## change to SECONDS_PER_GAME_MINUTE rescales deadlines in step with station
## timers. These are the previous hardcoded prototype-second values divided by
## the old 1/3 scale, so the relative pacing the game was built around is
## preserved exactly: Tier 1's 3600 game-minutes is ~12 full passes of the
## 302-game-minute pipeline, comfortable for a 3-8 part order.
const CONTRACT_DEADLINE_GAME_MINUTES := {
	Contract.ContractTier.LOCAL_SHOPS: 3600.0,
	Contract.ContractTier.REGIONAL_MANUFACTURERS: 5400.0,
	Contract.ContractTier.INDUSTRIAL_ACCOUNTS: 8100.0,
	Contract.ContractTier.FLAGSHIP: 16200.0,
}
const CONTRACT_PAYOUT_PER_UNIT := {
	Contract.ContractTier.LOCAL_SHOPS: 9.0,
	Contract.ContractTier.REGIONAL_MANUFACTURERS: 14.0,
	Contract.ContractTier.INDUSTRIAL_ACCOUNTS: 16.0,
	Contract.ContractTier.FLAGSHIP: 20.0,
}
## Rolled tier weights, index 0..3 for Tier 1..4 - weighted toward lower
## tiers even once higher ones are Reputation-unlocked, so the offered pool
## doesn't suddenly skew all-Flagship the moment a high threshold clears.
## First-pass placeholder, no basis in the doc beyond "smaller/faster jobs
## alongside bigger/slower ones" being the whole point of the tier overlap.
const CONTRACT_TIER_ROLL_WEIGHTS: Array[int] = [40, 30, 20, 10]


func can_afford(amount: int) -> bool:
	return currency >= amount


## Whether `amount` is affordable using gold alone OR gold topped up with
## gems at GEM_TO_CURRENCY_VALUE each - the check every purchase UI should
## use now, so a button doesn't stay disabled just because gold alone falls
## short while gems could cover the rest.
func can_afford_with_gems(amount: int) -> bool:
	if can_afford(amount):
		return true
	var shortfall := amount - currency
	var gems_needed := ceili(float(shortfall) / float(GEM_TO_CURRENCY_VALUE))
	return gems >= gems_needed


func upgrade_cost_for_tier(target_tier: int) -> int:
	if target_tier < 0 or target_tier >= STATION_TIER_UPGRADE_COST.size():
		return 0
	return STATION_TIER_UPGRADE_COST[target_tier]


func rack_upgrade_cost_for(target_capacity: int) -> int:
	if target_capacity < 0 or target_capacity >= STATION_RACK_UPGRADE_COST.size():
		return 0
	return STATION_RACK_UPGRADE_COST[target_capacity]


## Shared spend path: deducts and emits only if affordable. Returns whether
## the spend happened. Gold-only, no gem fallback - see try_spend_with_gems()
## below for the general-purpose path every real purchase now uses.
func try_spend(amount: int) -> bool:
	if not can_afford(amount):
		return false
	currency -= amount
	currency_changed.emit(currency)
	return true


## The real purchase path every spend call site now goes through (station
## tier/rack upgrades, technician/specialist hires, printer purchases,
## Mortar Patch/Redesign) - gold alone if it covers the cost, otherwise gold
## plus just enough gems to cover the shortfall (rounded up), never spending
## more gems than the shortfall actually requires. Fails cleanly (spends
## nothing) if even gold+gems together can't cover it.
func try_spend_with_gems(amount: int) -> bool:
	if try_spend(amount):
		return true
	if not can_afford_with_gems(amount):
		return false
	var shortfall := amount - currency
	var gems_needed := ceili(float(shortfall) / float(GEM_TO_CURRENCY_VALUE))
	currency = 0
	gems -= gems_needed
	currency_changed.emit(currency)
	gems_changed.emit(gems)
	return true


func register_part(part: Part) -> void:
	active_parts.append(part)


func unregister_part(part: Part) -> void:
	active_parts.erase(part)


## Learning-only parts (design doc 28.3) are excluded here and below: they
## can never ship, so counting them would stop the contract getting the
## replacement parts it still needs.
func count_parts_in_pipeline(contract_id: int) -> int:
	var count := 0
	for p in active_parts:
		if p.contract_id == contract_id and p.counts_toward_contract:
			count += 1
	return count


## Per-line-item in-flight counts for a contract (Section 24.1) - how many
## Parts already exist somewhere in the pipeline for each line item, keyed by
## line_item_index. Station._try_create_part() uses this to pick which line
## item still needs more Parts started for it - the same "shipped-or-in-
## flight, not just shipped" reasoning count_parts_in_pipeline() above
## already uses per-contract, just broken out per line item now.
func in_flight_counts_for_contract(contract_id: int) -> Dictionary:
	var counts := {}
	for p in active_parts:
		if p.contract_id == contract_id and p.counts_toward_contract:
			counts[p.line_item_index] = counts.get(p.line_item_index, 0) + 1
	return counts


## Bug fix (this session): a staffed entry station (or a player mashing
## Queue) used to keep creating brand new Parts as fast as its timer allowed,
## completely regardless of whether anything downstream could actually
## absorb them - GameData.held_parts has no cap of its own, so a clogged
## pipeline just meant an ever-growing pile of Awaiting Transfer Parts nobody
## could route anywhere. Reported as technicians "pumping out parts
## continuously" with "no stoppage." Every currently-flagged, unresolved
## defect counts here - first-pass placeholder threshold, same spirit as
## every other invented number in this file: the doc doesn't specify a
## number, just the design intent ("too many unanswered prompts for what the
## user wants to do about defective parts").
const MAX_UNRESOLVED_DEFECTS_BEFORE_PAUSE: int = 3

func count_unresolved_defects() -> int:
	var count := 0
	for part in active_parts:
		if part.is_defective:
			count += 1
	return count


func hold_part(part: Part) -> void:
	held_parts.append(part)
	held_parts_changed.emit()


func release_held_part(part: Part) -> void:
	held_parts.erase(part)
	held_parts_changed.emit()


## The station id a held (or otherwise in-transit) Part should move to next,
## or "" if it's already past the end of the line (shouldn't happen - Ship
## never holds parts, it ships them the instant they arrive).
func next_station_id_for(part: Part) -> String:
	var next_index := part.current_station_index + 1
	if next_index < 0 or next_index >= PIPELINE_ORDER.size():
		return ""
	return PIPELINE_ORDER[next_index]


## The specific geometry/alloy a Part is actually being made as - resolved
## through its contract's line_items, not a flat contract-level field any
## more (Section 24.1). Every caller that used to read
## `contract.geometry_name`/`alloy_name` directly off a Part's contract now
## goes through these two instead, since a contract can have several line
## items and a Part only ever belongs to one of them.
func geometry_name_for_part(part: Part) -> String:
	var contract := get_contract(part.contract_id)
	if contract == null:
		return ""
	var li := contract.line_item_at(part.line_item_index)
	return li.geometry_name if li != null else ""


func alloy_name_for_part(part: Part) -> String:
	var contract := get_contract(part.contract_id)
	if contract == null:
		return ""
	var li := contract.line_item_at(part.line_item_index)
	return li.alloy_name if li != null else ""


func get_active_contracts() -> Array[Contract]:
	return contracts.filter(func(c): return not c.is_complete)


## The first active contract that still needs a brand new Part started - i.e.
## has a line item whose shipped + in-flight count is short of its required
## quantity. null when every active contract is already fully covered by Parts
## in the pipeline. This is THE single answer to "can an entry station create a
## Part right now, contract-wise," shared by Station.has_actionable_work() (the
## routing predictor) and Station._try_create_part()/_auto_queue_if_possible()
## (the actor). They used to disagree: the predictor said yes whenever any
## active contract existed, while the actor only tried active[0] and refused
## once its line items were all in flight - so a technician covering two
## printers saw phantom work at whichever one they weren't standing at and
## walked back and forth between them forever.
# --- Print orders, quality and revert (design doc 28.7) --------------------
#
# Production no longer starts by itself: the player queues trial or
# production parts per contract line item (Contracts menu), paying per part,
# and printers - staffed or not - work through print_orders front to back.
# A trial part is poured in revert and never ships; a production part is
# poured in virgin metal, unlocked once the geometry is >= 85% familiar, and
# ships only at >= 90% quality. Every number here is a placeholder.

const SHIP_QUALITY_THRESHOLD: float = 90.0
const PRODUCTION_FAMILIARITY_PERCENT: float = 85.0
const STARTING_REVERT_STOCK: int = 10
const TRIAL_COST_SHARE: float = 0.2
const PRODUCTION_COST_SHARE: float = 0.5
const QUALITY_BASE: float = 55.0
const QUALITY_FAMILIARITY_SPAN: float = 40.0
const QUALITY_SPREAD: float = 6.0
const TRIAL_FIX_USES: int = 3
const ENGINEER_FIX_RISK_MULT := {
	Technician.SkillTier.APPRENTICE: 0.6,
	Technician.SkillTier.TECHNICIAN: 0.5,
	Technician.SkillTier.SENIOR_TECHNICIAN: 0.4,
	Technician.SkillTier.MASTER: 0.3,
}
const TRIAL_FAMILIARITY_GAIN := {
	Technician.SkillTier.APPRENTICE: 1,
	Technician.SkillTier.TECHNICIAN: 1,
	Technician.SkillTier.SENIOR_TECHNICIAN: 2,
	Technician.SkillTier.MASTER: 2,
}

## Remelted metal for trial pours. Saved.
var revert_stock: int = STARTING_REVERT_STOCK
## Queued, not-yet-printed parts, front first: {contract_id, line_item_index,
## is_trial, fix_station_id, fix_risk_mult}. Saved.
var print_orders: Array[Dictionary] = []
## contract_id -> {station_id, risk_mult, uses_left}: the Engineer's
## proposed fix from the latest diagnosis, stamped onto that contract's next
## TRIAL_FIX_USES trial parts as they're queued. Saved.
var pending_trial_fixes: Dictionary = {}

signal print_orders_changed()


## 0-100: the mean of the staff's average familiarity with the geometry and
## the shop-wide familiarity at the tracked stations, as a share of 5 stars.
func geometry_familiarity_percent(geometry_name: String) -> float:
	var staff := 0.0
	if not technicians.is_empty():
		for tech in technicians:
			staff += tech.shopwide_familiarity_for_geometry(geometry_name)
		staff /= technicians.size()
	var shop := 0.0
	for station_id in FAMILIARITY_TRACKED_STATIONS:
		shop += familiarity_stars_for(geometry_name, station_id)
	shop /= FAMILIARITY_TRACKED_STATIONS.size()
	return (staff + shop) * 0.5 / 5.0 * 100.0


func can_run_production(geometry_name: String) -> bool:
	return geometry_familiarity_percent(geometry_name) >= PRODUCTION_FAMILIARITY_PERCENT


func part_cost(contract: Contract, is_trial: bool) -> int:
	var per_unit: float = CONTRACT_PAYOUT_PER_UNIT.get(contract.tier, 10.0)
	return maxi(1, ceili(per_unit * (TRIAL_COST_SHARE if is_trial else PRODUCTION_COST_SHARE)))


func queued_order_count(contract_id: int, line_item_index: int, is_trial: bool) -> int:
	var count := 0
	for order in print_orders:
		if int(order.contract_id) == contract_id and int(order.line_item_index) == line_item_index and bool(order.is_trial) == is_trial:
			count += 1
	return count


## Production parts this line item still needs started: required, minus
## shipped, minus production parts already in the system or queued.
func production_still_needed(contract: Contract, line_item_index: int) -> int:
	var item: Contract.LineItem = contract.line_items[line_item_index]
	var in_flight: int = in_flight_counts_for_contract(contract.contract_id).get(line_item_index, 0)
	return item.quantity_required - item.quantity_shipped - in_flight - queued_order_count(contract.contract_id, line_item_index, false)


## "" if this part can be queued now, otherwise the reason it can't.
func print_order_blocker(contract: Contract, line_item_index: int, is_trial: bool) -> String:
	if not can_afford_with_gems(part_cost(contract, is_trial)):
		return "Not enough gold"
	if is_trial:
		if revert_stock <= 0:
			return "No revert metal left"
		return ""
	if not can_run_production(contract.line_items[line_item_index].geometry_name):
		return "Needs %d%% familiarity" % int(PRODUCTION_FAMILIARITY_PERCENT)
	if production_still_needed(contract, line_item_index) <= 0:
		return "Enough already queued"
	return ""


func queue_print_order(contract: Contract, line_item_index: int, is_trial: bool) -> bool:
	if print_order_blocker(contract, line_item_index, is_trial) != "":
		return false
	if not try_spend_with_gems(part_cost(contract, is_trial)):
		return false
	var order := {
		"contract_id": contract.contract_id,
		"line_item_index": line_item_index,
		"is_trial": is_trial,
		"fix_station_id": "",
		"fix_risk_mult": 1.0,
	}
	if is_trial:
		revert_stock -= 1
		var fix: Dictionary = pending_trial_fixes.get(contract.contract_id, {})
		if not fix.is_empty():
			order["fix_station_id"] = fix["station_id"]
			order["fix_risk_mult"] = fix["risk_mult"]
			fix["uses_left"] = int(fix["uses_left"]) - 1
			if fix["uses_left"] <= 0:
				pending_trial_fixes.erase(contract.contract_id)
	print_orders.append(order)
	print_orders_changed.emit()
	return true


## Whether a printer has something to start - the ONE predicate shared by
## Station.has_actionable_work(), _auto_queue_if_possible() and the manual
## Queue path, so the technician route predictor and the actor can't
## disagree (the root of every bounce bug - see CLAUDE.md).
func has_print_order() -> bool:
	_drop_stale_print_orders()
	return not print_orders.is_empty()


func pop_print_order() -> Dictionary:
	_drop_stale_print_orders()
	if print_orders.is_empty():
		return {}
	var order: Dictionary = print_orders.pop_front()
	print_orders_changed.emit()
	return order


## Orders whose contract has finished or gone are dropped (already paid -
## a finished contract simply doesn't need them).
func _drop_stale_print_orders() -> void:
	var before := print_orders.size()
	print_orders = print_orders.filter(func(order: Dictionary) -> bool:
		var contract := get_contract(int(order.contract_id))
		return contract != null and not contract.is_complete)
	if print_orders.size() != before:
		print_orders_changed.emit()


## Rolled once, when the part is poured (Station, at Pour).
func roll_casting_quality(part: Part) -> void:
	var share := geometry_familiarity_percent(geometry_name_for_part(part)) / 100.0
	part.quality = clampf(QUALITY_BASE + QUALITY_FAMILIARITY_SPAN * share + randf_range(-QUALITY_SPREAD, QUALITY_SPREAD), 0.0, 100.0)


## A trial part at the end of the line: remelted back to revert, and its
## lessons credited - more from a stronger Engineer (design doc 28.7).
func retire_trial_part(part: Part) -> void:
	revert_stock += 1
	var engineer := engineer_for_contract(part.contract_id)
	var stars: int = TRIAL_FAMILIARITY_GAIN.get(engineer.skill_tier, 1) if engineer != null else 1
	var geometry := geometry_name_for_part(part)
	for station_id in FAMILIARITY_TRACKED_STATIONS:
		raise_familiarity(geometry, station_id, stars)
	if engineer != null:
		engineer.gain_general_experience(geometry, stars)
	unregister_part(part)


## A production casting below SHIP_QUALITY_THRESHOLD: never shipped, saved as
## revert. The contract will need another production part queued.
func remelt_to_revert(part: Part) -> void:
	revert_stock += 1
	unregister_part(part)


func get_contract(id: int) -> Contract:
	for c in contracts:
		if c.contract_id == id:
			return c
	return null


## Credits one unit toward a contract's progress - specifically the one line
## item `part` was actually made for (Section 24.1: a contract can have
## several line items, only one of which this Part fulfills) - and pays out
## once the WHOLE contract (every line item) is fully shipped. Called from a
## Station when a part it's producing for that contract reaches Ship.
func credit_contract_shipment(contract: Contract, part: Part) -> void:
	if contract == null or contract.is_complete:
		return

	var line_item := contract.line_item_at(part.line_item_index)
	if line_item != null:
		line_item.quantity_shipped += 1
	if contract.is_complete:
		currency += contract.payout
		currency_changed.emit(currency)
		# Factory Level EXP (this session): awarded for completing the
		# contract at all, regardless of on-time status - a broader
		# condition than Reputation's own on-time-only gate just below.
		_award_factory_exp(contract.tier)
		# Design doc Section 8: "finishing contracts on time with a low
		# defect rate raises your reputation." A contract that already
		# tripped the missed-deadline penalty in _process_contracts() below
		# doesn't get a second reputation swing here for finishing anyway -
		# the miss already landed once, at the moment the deadline passed.
		if not contract.deadline_penalty_applied:
			_adjust_reputation(REPUTATION_GAIN_ON_TIME_COMPLETE)
			_adjust_relationship(contract.customer_name, RELATIONSHIP_GAIN_ON_TIME_COMPLETE)

	contract_updated.emit(contract)


func _adjust_reputation(delta: int) -> void:
	reputation = clampi(reputation + delta, 0, REPUTATION_MAX)
	reputation_changed.emit(reputation)


func relationship_stars_for(customer_name: String) -> float:
	return company_relationships.get(customer_name, 0.0)


func _adjust_relationship(customer_name: String, delta: float) -> void:
	var current: float = company_relationships.get(customer_name, 0.0)
	company_relationships[customer_name] = clampf(current + delta, 0.0, 5.0)


## Design doc Section 9's escalation point 2, the reputation half: "if it
## ships anyway, or sits long enough that it ships, the reputation hit lands
## on the contract." Previously stubbed since Reputation itself didn't exist
## - see Station._ship_part(), which now calls this right before discarding
## an unresolved-defective Part instead of crediting it.
func report_lost_defective_shipment(contract: Contract) -> void:
	_adjust_reputation(-REPUTATION_LOSS_DEFECTIVE_SHIP)
	if contract != null:
		_adjust_relationship(contract.customer_name, -RELATIONSHIP_LOSS_DEFECTIVE_SHIP)


func _max_eligible_tier() -> int:
	var best := 1
	for tier in REPUTATION_TIER_THRESHOLD.keys():
		if reputation >= REPUTATION_TIER_THRESHOLD[tier] and int(tier) > best:
			best = int(tier)
	return best


func _roll_contract_tier() -> int:
	var eligible_max := _max_eligible_tier()
	var total := 0
	for t in range(eligible_max):
		total += CONTRACT_TIER_ROLL_WEIGHTS[t]
	var roll := randi_range(1, total)
	var acc := 0
	for t in range(eligible_max):
		acc += CONTRACT_TIER_ROLL_WEIGHTS[t]
		if roll <= acc:
			return t + 1
	return eligible_max


func _average_relationship() -> float:
	if company_relationships.is_empty():
		return 0.0
	var total := 0.0
	for v in company_relationships.values():
		total += v
	return total / company_relationships.size()


## Section 8's "repeat clients" roll - returns a customer name already worked
## with, or "" if this contract should go to a brand new company instead.
func _maybe_pick_repeat_client() -> String:
	if company_relationships.is_empty():
		return ""
	var chance: float = clampf(
		REPEAT_CLIENT_BASE_CHANCE + (_average_relationship() / 5.0) * (REPEAT_CLIENT_MAX_CHANCE - REPEAT_CLIENT_BASE_CHANCE),
		REPEAT_CLIENT_BASE_CHANCE, REPEAT_CLIENT_MAX_CHANCE
	)
	if randf() >= chance:
		return ""
	var names := company_relationships.keys()
	return names[randi() % names.size()]


func _roll_new_customer_name(tier: int) -> String:
	var pool: Array = COMPANY_POOL.get(tier, [])
	if pool.is_empty():
		return "New Client %d" % (contracts.size() + 1)
	var used_names := {}
	for c in contracts:
		used_names[c.customer_name] = true
	var unused: Array = pool.filter(func(n): return not used_names.has(n))
	var candidates: Array = unused if not unused.is_empty() else pool
	return candidates[randi() % candidates.size()]


func _roll_geometry_for_tier(tier: int) -> String:
	var eligible_families: Array = []
	for family in FAMILY_MIN_TIER.keys():
		if int(FAMILY_MIN_TIER[family]) <= tier:
			eligible_families.append(family)
	if eligible_families.is_empty():
		eligible_families = FAMILY_MIN_TIER.keys()
	var family: String = eligible_families[randi() % eligible_families.size()]
	var parts: Array = GEOMETRY_POOL[family]
	return parts[randi() % parts.size()]


## Section 24.1: a contract can ask for several distinct geometries at once.
## Rolls `count` geometries independently (each its own family+part roll, so
## a single contract can genuinely span different families - design doc
## Section 24.1 asks for variety, not one family per contract), retrying a
## handful of times on a duplicate so the same geometry doesn't appear twice
## as two different line items on one contract. Not a hard guarantee at high
## counts against a small eligible pool, just a strong first-pass attempt.
func _roll_distinct_geometries_for_tier(tier: int, count: int) -> Array[String]:
	var picked: Array[String] = []
	for _i in count:
		var geometry := ""
		for _attempt in 5:
			geometry = _roll_geometry_for_tier(tier)
			if not picked.has(geometry):
				break
		picked.append(geometry)
	return picked


## Reverse lookup into GEOMETRY_POOL (keyed by family, not by geometry) -
## used both for the complexity tag below and for tinting a geometry's
## placeholder icon on the Contract Offers screen. "" for a geometry that
## somehow isn't in any pool (shouldn't happen in practice).
func family_for_geometry(geometry_name: String) -> String:
	for family in GEOMETRY_POOL.keys():
		if (GEOMETRY_POOL[family] as Array).has(geometry_name):
			return family
	return ""


## Section 10's family Complexity column, looked up via family_for_geometry()
## - "Medium"/"High"/etc. Falls back to "Medium" for an unrecognized geometry.
func complexity_label_for_geometry(geometry_name: String) -> String:
	return FAMILY_COMPLEXITY_LABEL.get(family_for_geometry(geometry_name), "Medium")


## Design doc Section 8: "randomized contract generation... company names and
## the part/alloy work they need are two fully separate pools, rolled
## independently rather than fixed pairs" plus "repeat clients" and "per-
## company relationship." Section 24.1 (this session): a contract can now ask
## for several distinct geometries at once, not just one. Called
## automatically from _process_contracts() whenever the offers pool runs low
## - see MIN_ACTIVE_CONTRACTS above. Builds an OFFER, not an active contract -
## see Section 24.9 / the Contract Offers screen: this no longer starts the
## deadline clock or joins the active `contracts` list on its own, the player
## has to accept_contract_offer() it first.
func generate_contract() -> Contract:
	var tier := _roll_contract_tier()
	var repeat_name := _maybe_pick_repeat_client()
	var customer: String
	if repeat_name != "":
		customer = repeat_name
		# Section 8: "at 5 stars a chance they offer something a tier above
		# what general Reputation would normally unlock." Design request
		# (this session): "the higher your company reputation the better
		# contracts you'll get from current companies you work with" - a
		# repeat client's own relationship still has to clear a real bar,
		# but that bar eases as shop-wide Reputation climbs, so a
		# well-regarded shop doesn't need every single returning client
		# maxed out at 5 stars before any of them offer better work.
		var bump_threshold: float = _repeat_client_tier_bump_threshold()
		if relationship_stars_for(customer) >= bump_threshold \
				and randf() < REPEAT_CLIENT_TIER_BUMP_CHANCE:
			tier = mini(tier + 1, Contract.ContractTier.FLAGSHIP)
	else:
		customer = _roll_new_customer_name(tier)

	var item_range: Vector2i = LINE_ITEM_COUNT_RANGE[tier]
	var item_count := randi_range(item_range.x, item_range.y)
	var geometries := _roll_distinct_geometries_for_tier(tier, item_count)
	# One alloy for the whole contract, not per line item - a customer's
	# order is one material spec, same as the real-world framing (design doc
	# Section 24.1's own example just says "steel," singular, for a
	# multi-part order).
	var alloy_pool: Array = ALLOY_POOL[tier]
	var alloy: String = alloy_pool[randi() % alloy_pool.size()]

	var quantity_range: Vector2i = CONTRACT_QUANTITY_RANGE[tier]
	# Divide the tier's existing whole-contract quantity range across however
	# many line items got rolled, so a multi-item contract's TOTAL size stays
	# in roughly the same ballpark as a single-item one used to be, rather
	# than multiplying the total ask by item_count on top of everything else.
	var per_item_range := Vector2i(
		maxi(1, quantity_range.x / item_count), maxi(1, quantity_range.y / item_count)
	)
	var reputation_bonus := 1.0 + (float(reputation) / float(REPUTATION_MAX)) * REPUTATION_QUALITY_BONUS_MAX

	var line_items: Array[Contract.LineItem] = []
	var total_quantity := 0
	for geometry in geometries:
		var li := Contract.LineItem.new()
		li.geometry_name = geometry
		li.alloy_name = alloy
		var qty := randi_range(per_item_range.x, per_item_range.y)
		# Same continuous Reputation-quality bonus as before, applied per
		# line item now rather than to one whole-contract number.
		qty = maxi(per_item_range.x, int(round(qty * reputation_bonus)))
		li.quantity_required = qty
		total_quantity += qty
		line_items.append(li)

	var payout := int(round(total_quantity * float(CONTRACT_PAYOUT_PER_UNIT[tier]) * randf_range(0.85, 1.15) * reputation_bonus))
	var deadline: float = game_minutes_to_seconds(CONTRACT_DEADLINE_GAME_MINUTES[tier])

	var offer := _make_contract(customer, tier, line_items, deadline, payout, false)
	contract_offers.append(offer)
	contract_offers_changed.emit()
	return offer


## Moves a rolled offer into real active work: starts its deadline clock
## (Contract.start(), deliberately not called until now - see that method's
## own comment), removes it from contract_offers, and appends it to
## `contracts` so get_active_contracts()/the backpressure and auto-queue
## logic all pick it up exactly like any other active contract from here on.
func accept_contract_offer(offer: Contract) -> void:
	if not contract_offers.has(offer):
		return
	contract_offers.erase(offer)
	offer.start()
	contracts.append(offer)
	contract_offers_changed.emit()
	contract_updated.emit(offer)


## Section 8's "at 5 stars" is the Reputation-0 baseline - eases down toward
## MIN_REPEAT_CLIENT_TIER_BUMP_STARS (3) as shop-wide Reputation climbs
## toward REPUTATION_MAX, so a well-regarded shop's repeat clients don't all
## individually need to be maxed out before any of them offer better work.
## First-pass placeholder shape, same spirit as every other invented curve
## in this file.
const MIN_REPEAT_CLIENT_TIER_BUMP_STARS: float = 3.0

func _repeat_client_tier_bump_threshold() -> float:
	var eased := REPEAT_CLIENT_TIER_BUMP_RELATIONSHIP_STARS - \
		(float(reputation) / float(REPUTATION_MAX)) * (REPEAT_CLIENT_TIER_BUMP_RELATIONSHIP_STARS - MIN_REPEAT_CLIENT_TIER_BUMP_STARS)
	return max(eased, MIN_REPEAT_CLIENT_TIER_BUMP_STARS)


## Sweeps every active contract for a deadline that just lapsed (Section 8:
## "missing deadlines... lowers reputation," a one-time penalty via
## Contract.deadline_penalty_applied so it doesn't refire every frame after),
## then tops the OFFERS pool back up via generate_contract() once it's run
## low, subject to a cooldown so a whole burst can't land at once. Filling
## the active pool itself is no longer automatic (see contract_offers/
## accept_contract_offer() above) - only offers get auto-generated; an offer
## only becomes real active work once the player accepts it.
func _process_contracts(delta: float) -> void:
	for c in contracts:
		# Burns the deadline clock (Contract.elapsed_seconds). Only started
		# contracts - an offer sitting in contract_offers hasn't been accepted
		# yet and must not lose time - and only incomplete ones, so a finished
		# contract's displayed time-left stops where it was rather than
		# drifting toward zero after the fact.
		if c.is_started and not c.is_complete:
			c.elapsed_seconds += delta
		if c.is_complete or c.deadline_penalty_applied:
			continue
		if c.is_overdue:
			c.deadline_penalty_applied = true
			_adjust_reputation(-REPUTATION_LOSS_MISSED_DEADLINE)
			_adjust_relationship(c.customer_name, -RELATIONSHIP_LOSS_MISSED_DEADLINE)
			contract_updated.emit(c)

	_contract_generation_cooldown = max(_contract_generation_cooldown - delta, 0.0)
	if _contract_generation_cooldown <= 0.0 and contract_offers.size() < MIN_ACTIVE_CONTRACTS:
		generate_contract()
		_contract_generation_cooldown = CONTRACT_GENERATION_COOLDOWN_SECONDS


## Assigns tech to station. Design request, this session: multiple
## technicians can now be assigned to the same station at once (previously
## this evicted whoever was there before) - Station.assigned_technicians is
## now an Array, and Station.active_worker (set the moment one of them is
## actually physically present) is what determines which single one of them
## is actually running the station at any given moment; the rest can still
## walk over to drop a carried part in the rack, but don't compete to work
## it - see Station._technician_act()/Technician._priority_tier_for() for the
## full coordination logic. tech itself can end up assigned to more than one
## station this way; see Technician.assigned_station_ids / productivity_multiplier
## for the walking penalty that creates (design doc Section 7).
func assign_technician(tech: Technician, station: Station) -> void:
	# Engineers own contracts, not stations (design doc 28.2).
	if tech.is_engineer or station.assigned_technicians.has(tech):
		return

	if not tech.assigned_station_ids.has(station.station_id):
		tech.assigned_station_ids.append(station.station_id)
	# Resolve where tech physically stands before the station reacts to being
	# staffed (auto-queue/claim-held-parts checks physical presence - see
	# Station._technician_is_present()), so a first/solo assignment goes live
	# immediately instead of waiting for next frame's _process() tick.
	tech.tick(0.0, station_by_id)
	station.assign_technician(tech)
	technician_updated.emit(tech)


## Frees station from tech without discharging tech from the roster - they
## stay hired and keep working anywhere else they're still assigned.
func unassign_technician(tech: Technician, station: Station) -> void:
	tech.assigned_station_ids.erase(station.station_id)
	station.unassign_technician(tech)
	tech.tick(0.0, station_by_id)
	technician_updated.emit(tech)


## Design request, this session: "i want the print station responsibility to
## cover all the printers not individual ones." Assigns tech to the virtual
## "printing" group entry (Technician.assigned_station_ids' own comment) and
## fans that out to every CURRENTLY owned printer's own assigned_technicians
## right now, since that's real per-Station bookkeeping the group entry
## can't represent by itself (Station._technician_act() needs to know who's
## actually assigned to iterate for presence checks). main.gd does the same
## fan-out for every already-group-assigned technician whenever a NEW
## printer is bought, so coverage stays automatic from then on without
## needing to touch this technician again.
func assign_technician_to_printer_group(tech: Technician) -> void:
	if not tech.assigned_station_ids.has("printing"):
		tech.assigned_station_ids.append("printing")
	for id in printer_station_ids():
		var station: Station = station_by_id.get(id)
		if station != null:
			station.assign_technician(tech)
	tech.tick(0.0, station_by_id)
	technician_updated.emit(tech)


func unassign_technician_from_printer_group(tech: Technician) -> void:
	tech.assigned_station_ids.erase("printing")
	for id in printer_station_ids():
		var station: Station = station_by_id.get(id)
		if station != null:
			station.unassign_technician(tech)
	tech.tick(0.0, station_by_id)
	technician_updated.emit(tech)



## Every real STAFFING TARGET a technician can be assigned to from the Shop
## roster - like all_real_station_ids() below, but collapses every printer
## instance into a single virtual "printing" entry (design request, this
## session), since checking each printer separately doesn't match how the
## player wants to think about staffing Printing as a whole. Every other
## entry is a concrete id exactly like all_real_station_ids() would give.
func assignable_station_group_ids() -> Array[String]:
	var ids: Array[String] = ["printing"]
	for id in PIPELINE_ORDER:
		if id != "printing":
			ids.append(id)
	return ids


## Advances every hired technician's real position/interact state
## (Technician.tick()) once per frame - the single place this is driven
## from, so a technician assigned to several stations only ever has one
## authoritative location regardless of how many Stations reference them.
## tick() only returns true on a discrete, UI-worth transition (arrival,
## interact start/end) - not on every incremental step of a walk, so this
## doesn't spam technician_updated 60 times a second while someone's mid-walk.
## True only while catch_up_offline_progress() is stepping the sim forward in
## slices. Station._process() checks it to skip its own visual work (there's
## nobody watching mid-catch-up, and the timer-bar text would be rewritten
## hundreds of times for one visible frame).
var is_catching_up: bool = false


func _process(delta: float) -> void:
	if is_catching_up:
		return
	# Stepped in slices for the same reason offline catch-up is: at high admin
	# speeds one frame's simulated time would let a walking technician
	# overshoot a station and skip its arrival logic.
	var remaining := delta * debug_sim_speed
	while remaining > 0.0:
		var step := minf(remaining, DEBUG_SIM_SLICE_SECONDS)
		simulate(step)
		remaining -= step


# --- Admin / test controls (the Admin overlay; debug builds only) ----------

## Game speed for testing (user request: "a slider to speed up the game so I
## can test without having to wait"). Multiplies every clock uniformly -
## stations, technicians, deadlines, defect timers - because it scales the
## delta fed to simulate() rather than any one duration. 0 pauses. Not saved.
var debug_sim_speed: float = 1.0
const DEBUG_SIM_SLICE_SECONDS: float = 0.25

enum DebugDefectMode { NORMAL, FORCE_NEXT, NONE }
## FORCE_NEXT makes the next roll at any defect-rolling station hit (then
## reverts to NORMAL); NONE suppresses every roll. Read by
## Station._roll_defect_outcome().
var debug_defect_mode: DebugDefectMode = DebugDefectMode.NORMAL


## Advances the whole simulation by seconds, in the same 0.25s slices as
## offline catch-up.
func debug_skip_ahead(seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.0:
		var step := minf(remaining, DEBUG_SIM_SLICE_SECONDS)
		simulate(step)
		remaining -= step


## Puts every running station run at its finish line; the next simulate()
## step completes them through the normal path.
func debug_finish_running_stations() -> void:
	for station: Station in station_by_id.values():
		station.debug_finish_run()


func debug_add_currency(amount: int) -> void:
	currency += amount
	currency_changed.emit(currency)


func debug_add_gems(amount: int) -> void:
	gems += amount
	gems_changed.emit(gems)


func debug_add_reputation(amount: int) -> void:
	reputation = clampi(reputation + amount, 0, REPUTATION_MAX)
	reputation_changed.emit(reputation)


func debug_exp_to_next_level() -> void:
	if is_factory_level_maxed():
		return
	factory_exp = maxi(factory_exp, factory_exp_for_level(factory_level + 1))
	factory_progress_changed.emit()


## The single steppable entry point for the whole simulation - every clock in
## the game advances from here and nowhere else. Split out of _process() for
## the save/load work so offline catch-up can drive the exact same code path
## with a synthetic delta instead of needing a second, parallel "what would
## have happened" model that could drift from the real one.
##
## Station logic is driven from here too, rather than each Station node
## running its own _process(): a Station's _process() now only paints
## visuals. That also makes the ordering deterministic (technicians move,
## then stations act on where they ended up, then defects and contracts
## settle), where before the relative order of GameData._process() and each
## Station._process() was whatever the SceneTree happened to pick.
func simulate(delta: float) -> void:
	stats_elapsed += delta
	for tech in technicians:
		if tech.tick(delta, station_by_id):
			technician_updated.emit(tech)

	for station: Station in station_by_id.values():
		station.simulate_step(delta)

	_process_engineers(delta)
	_process_contracts(delta)
	_process_applicant_pool(delta)


func record_station_run(station_id: String, cycle_seconds: float, flagged_defect: bool) -> void:
	var stats := _stats_for(station_id)
	stats.completed += 1
	stats.cycle_total += cycle_seconds
	if flagged_defect:
		stats.flagged += 1


func record_station_busy(station_id: String, delta: float) -> void:
	_stats_for(station_id).busy += delta


## Read-only view with derived numbers - every field defined even before the
## station has run once. yield_rate/utilization/per_hour are null-safe fractions.
func station_stat_summary(station_id: String) -> Dictionary:
	var stats: Dictionary = station_stats.get(station_id, {})
	var completed: int = stats.get("completed", 0)
	var flagged: int = stats.get("flagged", 0)
	var busy: float = stats.get("busy", 0.0)
	return {
		"completed": completed,
		"flagged": flagged,
		"avg_cycle_seconds": stats.get("cycle_total", 0.0) / completed if completed > 0 else 0.0,
		"yield_rate": 1.0 - float(flagged) / completed if completed > 0 else 1.0,
		"utilization": clampf(busy / stats_elapsed, 0.0, 1.0) if stats_elapsed > 0.0 else 0.0,
		"per_hour": completed / stats_elapsed * 3600.0 if stats_elapsed > 0.0 else 0.0,
	}


func _stats_for(station_id: String) -> Dictionary:
	if not station_stats.has(station_id):
		station_stats[station_id] = {"completed": 0, "flagged": 0, "cycle_total": 0.0, "busy": 0.0}
	return station_stats[station_id]


# --- Nonconformance shelf and Engineers (design doc Section 28) ------------

## Every defective part, the moment it's flagged (Station quarantines it via
## quarantine_part()). Saved as part ids, like held_parts.
var nc_shelf: Array[Part] = []
## Scrapped parts, counted only - the "scrap inventory" itself is a later idea
## (design doc 28.3).
var scrapped_part_count: int = 0

## Base diagnosis time for an Apprentice-tier Engineer, before speed bonuses.
const DIAGNOSIS_GAME_MINUTES: float = 10.0
const ENGINEER_DIAGNOSIS_SPEED := {
	Technician.SkillTier.APPRENTICE: 1.0,
	Technician.SkillTier.TECHNICIAN: 1.25,
	Technician.SkillTier.SENIOR_TECHNICIAN: 1.5,
	Technician.SkillTier.MASTER: 2.0,
}
## Each undiagnosed shelf part raises the defect risk at the station that
## flagged it by this fraction of its normal risk (design doc 28.1: "other
## parts coming through will also have a chance to have that defect occur"),
## up to UNDIAGNOSED_RISK_MAX_MULTIPLIER.
const UNDIAGNOSED_RISK_PER_PART: float = 0.5
const UNDIAGNOSED_RISK_MAX_MULTIPLIER: float = 3.0
## An idle Engineer earns one star of familiarity on each of their contracts'
## geometries per this many game minutes (design doc 28.2).
const PASSIVE_LEARNING_GAME_MINUTES: float = 60.0
const FAMILIARITY_GAIN_DIAGNOSIS: int = 1
const FAMILIARITY_GAIN_LEARNING_SCAN: int = 1


func quarantine_part(part: Part) -> void:
	if not nc_shelf.has(part):
		nc_shelf.append(part)
	nc_shelf_changed.emit()


## Where a diagnosed part can be reworked (design doc 28.3: printer defects at
## Patching, shell cracks at Mold Prep), or "" if its defect can't be - those
## can only be scrapped or scanned to learn.
func rework_station_for(part: Part) -> String:
	if part.defect_category == DefectCategory.SHELL_CRACK:
		return "mold_prep"
	if part.defect_station_id.begins_with("printing"):
		return "patching"
	return ""


func undiagnosed_risk_multiplier(station_id: String) -> float:
	var count := 0
	for part in nc_shelf:
		if not part.nc_diagnosed and part.defect_station_id == station_id:
			count += 1
	return minf(1.0 + UNDIAGNOSED_RISK_PER_PART * count, UNDIAGNOSED_RISK_MAX_MULTIPLIER)


func engineers() -> Array[Technician]:
	var out: Array[Technician] = []
	for tech in technicians:
		if tech.is_engineer:
			out.append(tech)
	return out


func engineer_for_contract(contract_id: int) -> Technician:
	for tech in technicians:
		if tech.is_engineer and tech.assigned_contract_ids.has(contract_id):
			return tech
	return null


## One Engineer per contract; null clears it.
func assign_engineer_to_contract(contract_id: int, engineer: Technician) -> void:
	for tech in technicians:
		tech.assigned_contract_ids.erase(contract_id)
	if engineer != null and engineer.is_engineer:
		engineer.assigned_contract_ids.append(contract_id)
	nc_shelf_changed.emit()


func diagnosis_seconds_for(engineer: Technician) -> float:
	var speed: float = ENGINEER_DIAGNOSIS_SPEED.get(engineer.skill_tier, 1.0) * engineer.seniority_speed_multiplier
	return game_minutes_to_seconds(DIAGNOSIS_GAME_MINUTES) / maxf(speed, 0.1)


## The shelf part this Engineer is diagnosing (or would diagnose next):
## the oldest undiagnosed one from a contract they own.
func diagnosis_target_for(engineer: Technician) -> Part:
	for part in nc_shelf:
		if not part.nc_diagnosed and engineer.assigned_contract_ids.has(part.contract_id):
			return part
	return null


## Diagnosis runs in the background for now (design doc 28.2 - the
## engineering-office scene comes later): each Engineer works on one shelved
## part from their own contracts at a time, and when they have none, slowly
## learns their contracts' geometries instead.
func _process_engineers(delta: float) -> void:
	for engineer in engineers():
		var part := diagnosis_target_for(engineer)
		if part != null:
			part.nc_diagnosis_elapsed += delta
			if part.nc_diagnosis_elapsed >= diagnosis_seconds_for(engineer):
				_finish_diagnosis(part, engineer)
			continue
		if engineer.assigned_contract_ids.is_empty():
			continue
		engineer.passive_learning_elapsed += delta
		if engineer.passive_learning_elapsed < game_minutes_to_seconds(PASSIVE_LEARNING_GAME_MINUTES):
			continue
		engineer.passive_learning_elapsed = 0.0
		for contract_id in engineer.assigned_contract_ids:
			var contract := get_contract(contract_id)
			if contract == null or contract.is_complete:
				continue
			for item in contract.line_items:
				engineer.gain_general_experience(item.geometry_name, 1)
		technician_updated.emit(engineer)


func _finish_diagnosis(part: Part, engineer: Technician) -> void:
	part.nc_diagnosed = true
	# The Engineer proposes a fix for the next trial batch (design doc 28.7).
	pending_trial_fixes[part.contract_id] = {
		"station_id": part.defect_station_id,
		"risk_mult": ENGINEER_FIX_RISK_MULT.get(engineer.skill_tier, 0.6),
		"uses_left": TRIAL_FIX_USES,
	}
	var geometry := geometry_name_for_part(part)
	raise_familiarity(geometry, part.defect_station_id, FAMILIARITY_GAIN_DIAGNOSIS)
	engineer.gain_general_experience(geometry, FAMILIARITY_GAIN_DIAGNOSIS)
	technician_updated.emit(engineer)
	nc_shelf_changed.emit()


## Disposition: scrap. Allowed with or without a diagnosis (you just learn
## nothing). The contract will start a replacement part on its own.
func scrap_nc_part(part: Part) -> void:
	nc_shelf.erase(part)
	unregister_part(part)
	scrapped_part_count += 1
	nc_shelf_changed.emit()


## Disposition: rework for learning (design doc 28.3). Back onto the line
## from the station after the one that flagged it - via Awaiting Transfer,
## so technicians or the player carry it - repaired on the way at
## rework_station_for(), but learning-only: it never ships.
func rework_nc_part(part: Part) -> bool:
	if not part.nc_diagnosed or rework_station_for(part) == "":
		return false
	_release_for_learning(part)
	return true


## Disposition for a defect that can't be reworked: send it to Structured
## Light Scan to learn from it; it's retired once scanned.
func scan_nc_part(part: Part) -> bool:
	if not part.nc_diagnosed or rework_station_for(part) != "":
		return false
	part.scan_to_learn = true
	part.current_station_index = PIPELINE_ORDER.find("scan") - 1
	_release_for_learning(part)
	return true


func _release_for_learning(part: Part) -> void:
	part.learning_only = true
	part.learning_origin_station_id = part.defect_station_id
	part.clear_defect()
	nc_shelf.erase(part)
	part.status = Part.Status.READY_TO_ROUTE
	hold_part(part)
	nc_shelf_changed.emit()


## A learning-only part reaching the end of its usefulness (Ship, or Scan
## for scan_to_learn): retired, never credited.
func retire_learning_part(part: Part, at_station_id: String) -> void:
	if part.scan_to_learn:
		raise_familiarity(geometry_name_for_part(part), part.learning_origin_station_id, FAMILIARITY_GAIN_LEARNING_SCAN)
	unregister_part(part)


func _init() -> void:
	stations = [
		# Printing is spawned specially by main.gd as N independent purchasable
		# instances (design doc Section 21.2) rather than one Station per this
		## entry - this StationDef is only the shared Tier 1 template every new
		# printer instance is stamped from (see GameData.PRINTER_DEF /
		# buy_printer()). Kept in this array too so get_station("printing")
		# still resolves for anything that just needs the display name/room
		# (e.g. Structured Light Scan's next-station label), even though no
		# single live Station node ever has station_id=="printing" itself.
		StationDef.new("printing", "Printing", Station.StationType.QUEUE,
			1, "Print Room", 15.0, 1, PRINTING_SPRITES),
		# New this session (design doc Section 21.4): every part passes through,
		# batched, no defect risk of its own - removes excess resin before UV Cure.
		StationDef.new("clean", "Clean", Station.StationType.BATCHED,
			1, "Print Room", 8.0, 5, [], CLEAN_STATE_SPRITES, CLEAN_SPRITE_SCALE_OVERRIDE),
		StationDef.new("uv_cure", "UV Cure", Station.StationType.BATCHED,
			1, "Print Room", 12.0, 6),
		StationDef.new("scan", "Structured Light Scan", Station.StationType.QUEUE,
			1, "Print Room", 2.0, 1),
		# New this session (design doc Section 21.4): every part passes through,
		# not batched, no player decision - auto-resolves any printer-sourced
		# defect, quality scaling with the assigned technician's skill (see
		# Station._resolve_patching()). Also the mechanical reason Printing's
		# "no decline option" holds: this always runs and always resolves.
		StationDef.new("patching", "Patching", Station.StationType.QUEUE,
			1, "Print Room", 6.0, 1),

		StationDef.new("pour_cup_attach", "Pour Cup Attach", Station.StationType.QUEUE,
			2, "Shell Building", 3.0, 1),
		# Design doc Section 4 (revised this session): single part at Tier 1,
		# not batched - Tier 2+ replaces batching entirely with parallel
		# independent per-part timers (see Station.shelling_active_parts), a
		# genuinely different runtime model rather than a bigger batch_cap.
		# One combined timer at Tier 1. 30 game-minutes = 60 real seconds (user
		# decision 2026-10-03) - was Section 17's 160 (320s), over half the
		# whole pipeline. Still the longest step.
		StationDef.new("shelling", "Shelling", Station.StationType.QUEUE,
			2, "Shell Building", 30.0, 1),

		StationDef.new("burnout", "Burnout", Station.StationType.BATCHED,
			3, "Furnace Room", 45.0, 8, BURNOUT_SPRITES),
		# New this session (design doc Section 21.4): every part passes through,
		# not batched - this is where Mortar Patch now specifically happens
		# (shell cracks from Shelling or Burnout), and the natural home for a
		# future insulation-decision mechanic ahead of Pour.
		StationDef.new("mold_prep", "Mold Prep", Station.StationType.QUEUE,
			3, "Furnace Room", 6.0, 1),

		StationDef.new("pour", "Pour", Station.StationType.QUEUE,
			4, "Pour Room", 20.0, 3, POUR_SPRITES),

		StationDef.new("deshell", "Deshell", Station.StationType.QUEUE,
			5, "Post Processing", 5.0, 1),
		# New this session (design request: "i want to add grinding to the
		# post process room. grinding can cause a defect") - grinds off
		# gates/sprues after shell removal, before the final surface blast.
		# Single part at Tier 1 like Deshell, not batched.
		StationDef.new("grinding", "Grinding", Station.StationType.QUEUE,
			5, "Post Processing", 8.0, 1),
		# Design doc Section 4 (revised this session): single part at Tier 1,
		# batching unlocks Tier 2+ (see GameData.ABRASIVE_BLAST_TIER_BATCH_CAP).
		StationDef.new("abrasive_blast", "Abrasive Blast", Station.StationType.BATCHED,
			5, "Post Processing", 12.0, 1),
		# Unlimited batch cap, represented as -1.
		StationDef.new("ship", "Ship", Station.StationType.AUTOMATIC,
			5, "Post Processing", 0.0, -1),
	]

	# The six starting contracts from Section 9. Section 7 only gives
	# qualitative deadline/payout per tier (Generous/Moderate/Tighter/Tight,
	# Low/Medium/High/Very High) - concrete numbers below are first-pass
	# placeholders scaled to that, same spirit as the Technician costs.
	# Direct request, this session: "there shouldn't be any active contracts
	# when you start" - these load as unaccepted OFFERS now, same as any
	# generated one, rather than immediately active with a running deadline
	# clock. accept_contract_offer() is what actually starts each one.
	contract_offers = [
		_make_single_item_contract("Local Hardware Co.", Contract.ContractTier.LOCAL_SHOPS,
			"Mounting Brackets", "Mild Steel", 5, game_minutes_to_seconds(3600.0), 50),
		_make_single_item_contract("Riverside Jewelers", Contract.ContractTier.LOCAL_SHOPS,
			"Pendant Blanks", "Bronze", 8, game_minutes_to_seconds(3600.0), 70),
		_make_single_item_contract("Cascade Fluid Systems", Contract.ContractTier.REGIONAL_MANUFACTURERS,
			"Valve Bodies", "Stainless Steel", 15, game_minutes_to_seconds(5400.0), 220),
		_make_single_item_contract("Northline Pumps Inc.", Contract.ContractTier.REGIONAL_MANUFACTURERS,
			"Pump Housings", "Cast Iron Blend", 20, game_minutes_to_seconds(5400.0), 280),
		_make_single_item_contract("Summit Industrial Group", Contract.ContractTier.INDUSTRIAL_ACCOUNTS,
			"Gear Housings", "Alloy Steel", 40, game_minutes_to_seconds(8100.0), 650),
		# Recurring flagship work isn't modeled yet - this is a one-time
		# contract for now, same as the other five.
		_make_single_item_contract("Meridian Aerospace", Contract.ContractTier.FLAGSHIP,
			"Turbine Blades", "Nickel Superalloy", 120, game_minutes_to_seconds(16200.0), 2500),
	]

	# Staff overlay should never open to an empty applicant pool.
	_refill_applicant_pool()


## `auto_start`: true for the six immediately-active starting contracts
## (start() runs right away, same as before this session), false for a
## generated offer (Contract.start() waits for accept_contract_offer()).
func _make_contract(
	customer: String,
	tier: Contract.ContractTier,
	line_items: Array[Contract.LineItem],
	deadline_seconds: float,
	payout: int,
	auto_start: bool = true
) -> Contract:
	var c := Contract.new()
	c.customer_name = customer
	c.tier = tier
	c.line_items = line_items
	c.deadline_seconds = deadline_seconds
	c.payout = payout
	if auto_start:
		c.start()
	return c


## Convenience for a single-geometry contract (the six starting contracts
## above) - builds the one-element line_items array _make_contract() now
## expects, so those call sites don't need to construct a LineItem by hand.
## auto_start=false: these load as offers now, not immediately-active
## contracts (see the comment above the six starting contracts).
func _make_single_item_contract(
	customer: String,
	tier: Contract.ContractTier,
	geometry: String,
	alloy: String,
	quantity: int,
	deadline_seconds: float,
	payout: int
) -> Contract:
	var li := Contract.LineItem.new()
	li.geometry_name = geometry
	li.alloy_name = alloy
	li.quantity_required = quantity
	var items: Array[Contract.LineItem] = [li]
	return _make_contract(customer, tier, items, deadline_seconds, payout, false)


## Falls back to the shared "printing" template for any specific printer
## instance id ("printing_1", "printing_2", ...) - no live Station node ever
## has station_id=="printing" itself (see PIPELINE_ORDER's comment), but
## anything that just wants the shared display name/room/sprites still
## resolves correctly this way.
func get_station(id: String) -> StationDef:
	var lookup_id := "printing" if id.begins_with("printing") else id
	for s in stations:
		if s.id == lookup_id:
			return s
	return null


## Design doc Section 21.2: printers are purchased individually rather than
## upgrading one shared Printing station. Starts at 1 - every new shop starts
## with one working printer, same as it always had exactly one Printing
## station before this rework - raised via buy_printer() up to printer_cap().
## Each owned printer becomes its own live Station instance (station ids
## "printing_1".."printing_N", spawned/despawned by main.gd), independently
## tiered exactly like any other station - current_tier already lives per
## Station instance, nothing new was needed there for that part.
var owned_printer_count: int = 1

## "the number of printers a player is allowed to own is capped by factory
## level... a Level 1 factory allows 2 printers" (Section 21.2) - the only
## concrete number given; levels 2-5 are a first-pass placeholder extending
## the same +1-per-level shape, matching PRINTER_PURCHASE_COST's own
## existing headroom for up to 5 owned printers (see its own comment).
var factory_level: int = 1
const FACTORY_LEVEL_MAX: int = 5
const FACTORY_LEVEL_PRINTER_CAP := {1: 2, 2: 3, 3: 4, 4: 5, 5: 6}

func printer_cap() -> int:
	return FACTORY_LEVEL_PRINTER_CAP.get(factory_level, FACTORY_LEVEL_PRINTER_CAP[1])


## Originally "no currency to upgrade factory level" (an earlier session's
## design request) - reversed this session ("change how you get to the next
## factory level by paying a price"). factory_exp is now a lifetime,
## never-spent ELIGIBILITY total, still awarded whenever a contract fully
## ships - crossing a level's threshold (FACTORY_LEVEL_EXP_THRESHOLD below)
## no longer levels up by itself, it just unlocks the ABILITY to pay for that
## level (can_level_up_factory()/level_up_factory() below), same two-step
## shape contract_offers/applicant_pool already use elsewhere in this file
## (roll/unlock first, a separate deliberate spend actually claims it).
var factory_exp: int = 0

## First-pass placeholder EXP-per-tier table, scaled the same direction as
## every other tier-keyed table in this file (CONTRACT_PAYOUT_PER_UNIT,
## CONTRACT_QUANTITY_RANGE) - a bigger, harder-to-land contract is worth
## more EXP. Section 8/21 give no numbers for this since the mechanic didn't
## exist before this session.
const FACTORY_EXP_PER_CONTRACT_TIER := {
	Contract.ContractTier.LOCAL_SHOPS: 10,
	Contract.ContractTier.REGIONAL_MANUFACTURERS: 25,
	Contract.ContractTier.INDUSTRIAL_ACCOUNTS: 60,
	Contract.ContractTier.FLAGSHIP: 150,
}

## Cumulative lifetime EXP required to BE at a given level - level N is
## reached the moment factory_exp crosses this table's entry for N. A
## first-pass placeholder curve, same invented-but-reasonable spirit as
## every other cost/threshold table in this file.
const FACTORY_LEVEL_EXP_THRESHOLD := {
	1: 0,
	2: 150,
	3: 400,
	4: 900,
	5: 1800,
}

func factory_exp_for_level(level: int) -> int:
	return FACTORY_LEVEL_EXP_THRESHOLD.get(level, FACTORY_LEVEL_EXP_THRESHOLD[FACTORY_LEVEL_MAX])


func is_factory_level_maxed() -> bool:
	return factory_level >= FACTORY_LEVEL_MAX


## Called once per fully-shipped contract (see credit_contract_shipment()) -
## awards EXP regardless of whether the contract was on time, since
## "completing" a contract is a broader condition than the on-time-only gate
## Reputation itself uses. No longer auto-levels on its own (design request,
## this session: "change how you get to the next factory level by paying a
## price") - crossing a threshold now only makes the player ELIGIBLE
## (can_level_up_factory() below); level_up_factory() is the one place
## factory_level actually moves, and it's a deliberate, paid player action.
## EXP itself keeps accumulating past the next threshold with no cap, so a
## big contract that clears two levels' worth at once just leaves the player
## able to immediately pay for a second level-up right after the first.
func _award_factory_exp(tier: Contract.ContractTier) -> void:
	factory_exp += FACTORY_EXP_PER_CONTRACT_TIER.get(tier, FACTORY_EXP_PER_CONTRACT_TIER[Contract.ContractTier.LOCAL_SHOPS])
	factory_progress_changed.emit()


func can_level_up_factory() -> bool:
	return not is_factory_level_maxed() and factory_exp >= factory_exp_for_level(factory_level + 1)


## First-pass placeholder "factory expansion" price, keyed by the level being
## bought INTO (2..5) - Section 20 gives no numbers since paying to level up
## didn't exist before this session. Priced above PRINTER_PURCHASE_COST's own
## top end since leveling the whole factory (faster processes shop-wide, a
## higher printer cap) is a bigger deal than any single purchase.
const FACTORY_LEVEL_UP_PRICE := {2: 400, 3: 800, 4: 1400, 5: 2200}

func factory_level_up_price() -> int:
	if is_factory_level_maxed():
		return 0
	return FACTORY_LEVEL_UP_PRICE.get(factory_level + 1, 0)


func can_afford_factory_level_up() -> bool:
	return can_level_up_factory() and can_afford_with_gems(factory_level_up_price())


## Design request, this session: leveling up now costs real currency (the
## "price" above, gold-first-then-gems like every other real purchase) AND
## triggers a full payroll payment - "you have to pay your technicians
## salary when you level up." Order matters: tenure/skill first, THEN
## payroll, so the payout reflects the raise this exact level-up just
## granted (Technician.wage grows with factory_levels_stuck_with_you) -
## narratively, leveling up is a promotion event, and everyone who stuck
## around gets both a raise and their bonus check in the same moment. The
## price itself is a hard affordability gate (can_afford_factory_level_up()
## above); the payroll portion is NOT - it force-deducts the same
## debt-capable way the old standing wage tick did (see
## is_in_wage_debt()), since "you have to pay" shouldn't itself block the
## level-up that triggered it.
func level_up_factory() -> bool:
	if not can_afford_factory_level_up():
		return false
	if not try_spend_with_gems(factory_level_up_price()):
		return false
	factory_level += 1
	for tech in technicians:
		tech.factory_levels_stuck_with_you += 1
	var payroll := total_wage_payroll()
	if payroll > 0:
		currency -= payroll
		currency_changed.emit(currency)
		payday.emit(payroll, currency < 0)
	# The one gem source that exists so far - a genuine milestone reward, not
	# routine contract income, matching "harder to get."
	gems += FACTORY_LEVEL_UP_GEM_REWARD
	gems_changed.emit(gems)
	factory_progress_changed.emit()
	return true


## "Your processes get faster" (design request, this session) - a shop-wide
## timer speed-up applied on top of everything station-specific
## (Technician.productivity_multiplier, Technician.seniority_speed_multiplier),
## read by Station._effective_timer_duration() regardless of staffing, so it
## benefits unstaffed/automatic stations too. First-pass placeholder rate;
## tops out at FACTORY_LEVEL_MAX (5) => 1.0 + 0.08*4 = 1.32x.
const FACTORY_LEVEL_SPEED_BONUS_PER_LEVEL: float = 0.08

func factory_process_speed_multiplier() -> float:
	return 1.0 + FACTORY_LEVEL_SPEED_BONUS_PER_LEVEL * (factory_level - 1)


func can_buy_printer() -> bool:
	return owned_printer_count < printer_cap()


## First-pass placeholder cost curve for buying an additional printer -
## Section 21.2 gives no numbers. Priced in the same ballpark as a station
## tier upgrade (STATION_TIER_UPGRADE_COST) since a whole new machine is a
## bigger buy than a single tier step. Index = the printer being bought
## (1-based - buying the 2nd printer reads index 2); index 0-1 unused since
## the 1st printer is already owned for free at game start.
const PRINTER_PURCHASE_COST: Array[int] = [0, 0, 250, 450, 750, 1100, 1500]

func printer_purchase_cost() -> int:
	var next_index: int = clampi(owned_printer_count + 1, 0, PRINTER_PURCHASE_COST.size() - 1)
	return PRINTER_PURCHASE_COST[next_index]


## Fires once a purchase actually goes through, carrying the new total
## owned_printer_count - main.gd listens for this to spawn the new printer's
## live Station instance immediately rather than requiring a scene reload.
signal printer_purchased(new_owned_count: int)


func buy_printer() -> bool:
	if not can_buy_printer():
		return false
	if not try_spend_with_gems(printer_purchase_cost()):
		return false
	owned_printer_count += 1
	printer_purchased.emit(owned_printer_count)
	return true


## Real per-instance ids for every owned printer, "printing_1".."printing_N" -
## PIPELINE_ORDER only has one generic "printing" placeholder entry (see its
## own comment), so anything that needs to walk every actual live printer
## Station needs this instead.
func printer_station_ids() -> Array[String]:
	var ids: Array[String] = []
	for i in owned_printer_count:
		ids.append("printing_%d" % (i + 1))
	return ids


## Every real station id that actually has a live Station node right now:
## every owned printer instance, plus every other PIPELINE_ORDER entry except
## the "printing" placeholder itself (which has no single matching node - see
## printer_station_ids() above). UI that needs to walk every real station
## (StaffOverlay's technician assignment checkboxes, FactoryOverlay and BoardOverlay lists)
## uses this instead of PIPELINE_ORDER directly.
func all_real_station_ids() -> Array[String]:
	var ids := printer_station_ids()
	for id in PIPELINE_ORDER:
		if id != "printing":
			ids.append(id)
	return ids


## 0.0 (no roll ever happens) for any station not in STATION_BASE_DEFECT_RISK.
## Printer instances are "printing_1", "printing_2"... but the defect tables
## are keyed by the shared "printing" template. Without this, printers never
## rolled a defect at all.
func defect_table_key(station_id: String) -> String:
	return "printing" if station_id.begins_with("printing_") else station_id


func base_defect_risk_for(station_id: String) -> float:
	return STATION_BASE_DEFECT_RISK.get(defect_table_key(station_id), 0.0)


## 0 for any geometry/station pair never raised, or for any station_id not in
## FAMILIARITY_TRACKED_STATIONS (Printing included - see the field comment above).
func familiarity_stars_for(geometry_name: String, station_id: String) -> int:
	var per_station: Dictionary = geometry_familiarity.get(geometry_name, {})
	return per_station.get(station_id, 0)


## 1.0 (no reduction at all) for any station_id not in
## FAMILIARITY_TRACKED_STATIONS. This is now only the OLD shop-wide path,
## used by Station._roll_defect_outcome() specifically for the two stations
## that stayed on it (Burnout, Mold Prep - see department_for_station()
## below) - every other defect-rolling station reads familiarity_multiplier_for_worker()
## instead now.
func familiarity_multiplier_for(geometry_name: String, station_id: String) -> float:
	if not FAMILIARITY_TRACKED_STATIONS.has(station_id):
		return 1.0
	return FAMILIARITY_MULTIPLIER[familiarity_stars_for(geometry_name, station_id)]


## Which per-worker "department" a station belongs to for the new per-staff
## familiarity system (design request, this session) - "" means no mapping,
## i.e. this station stays on the OLD shop-wide familiarity_multiplier_for()
## path above untouched. Burnout and Mold Prep are deliberately absent - the
## user named exactly 5 departments; those two keep today's behavior exactly
## as it was. Post Processing's four stations (only Grinding actually rolls
## a defect; Deshell/Abrasive Blast/Ship are purely mechanical) all share one
## "post_process" department, matching the mockup's own 3-department
## grouping once Pour moved under Engineer.
const STATION_DEPARTMENT := {
	"printing": "printing",
	"shelling": "shelling",
	"pour": "pour",
	"patching": "patching",
	"deshell": "post_process",
	"abrasive_blast": "post_process",
	"ship": "post_process",
	"grinding": "post_process",
}

func department_for_station(station_id: String) -> String:
	return STATION_DEPARTMENT.get(station_id, "")


## The new per-staff-member counterpart to familiarity_multiplier_for()
## above - used for every station with a real department_for_station()
## mapping. Staffed: the specific worker's own familiarity_for_geometry()
## (the whole point - "each time they process a part... they gain some
## amount of familiarity," and it's THEIR run, not a shop average).
## Unstaffed: nobody specific is running it, so this falls back to the same
## shop-wide average_familiarity_stars() shown on the contract, rather than
## reading nobody's personal value.
func familiarity_multiplier_for_worker(geometry_name: String, department_name: String, worker: Technician) -> float:
	var stars: int
	if worker != null:
		stars = worker.familiarity_for_geometry(geometry_name, department_name)
	else:
		stars = average_familiarity_stars(geometry_name)
	return FAMILIARITY_MULTIPLIER[stars]


## First-pass placeholder per-run experience gain (design request: "each
## time they process a part of a certain geometry they gain some amount of
## familiarity with that geometry") - deliberately small, so meaningfully
## raising a specific geometry's familiarity above a worker's flat
## department_skill baseline takes genuine repeat work, not one lucky part.
const EXPERIENCE_GAIN_PER_RUN: int = 1


## Bumps geometry_name's familiarity at station_id up by stars, capped at 5
## (never lowered here - nothing in this pass ever reduces familiarity). A
## no-op for station_id not in FAMILIARITY_TRACKED_STATIONS (design doc
## Section 21.7 only tracks Shelling/Burnout/Mold Prep/Pour) - callers don't
## need to check eligibility themselves. Called by the fix paths below and by
## Station._resolve_push_through() (now generalized beyond Pour - design doc
## Section 21.6); a plain successful run never calls this on its own.
func raise_familiarity(geometry_name: String, station_id: String, stars: int) -> void:
	if geometry_name == "" or not FAMILIARITY_TRACKED_STATIONS.has(station_id):
		return
	if not geometry_familiarity.has(geometry_name):
		geometry_familiarity[geometry_name] = {}
	var per_station: Dictionary = geometry_familiarity[geometry_name]
	per_station[station_id] = clampi(per_station.get(station_id, 0) + stars, 0, 5)


## Reworked this session (design request: "the familiarity rating you see on
## the contract is the average familiarity of your technicians and engineers
## as well as R&D eventually when we build that out") - was previously a
## single average across the 4 FAMILIARITY_TRACKED_STATIONS (shop-wide, no
## staff involved at all); now averages every hired Technician/Engineer's OWN
## familiarity_stars_for_staff() below instead. Same signature/rounding as
## before, so every existing call site (Contracts Offers screen, Station
## Detail Menu tooltips) keeps working unchanged - only what the number
## MEANS changed. Falls back to 0 if nobody's hired yet (can't average an
## empty roster) - R&D's own contribution isn't built yet, noted for when it
## is (Section 12).
func average_familiarity_stars(geometry_name: String) -> int:
	if technicians.is_empty():
		return 0
	var total := 0.0
	for tech in technicians:
		total += tech.shopwide_familiarity_for_geometry(geometry_name)
	return roundi(total / technicians.size())


## The single lowest-familiarity staff member for this geometry, not the
## lowest-familiarity STATION anymore (same rework as average_familiarity_stars()
## above, same reasoning: Section 21.7's "an average could otherwise hide a
## real problem area" now applies to your weakest-familiarity hire, not your
## weakest-covered station).
func weakest_familiarity_stars(geometry_name: String) -> int:
	if technicians.is_empty():
		return 0
	var weakest := 5.0
	for tech in technicians:
		weakest = min(weakest, tech.shopwide_familiarity_for_geometry(geometry_name))
	return roundi(weakest)


## The weakest-link station's familiarity expressed as a percentage (0/5
## stars = 0%, 5/5 = 100%) - design doc Section 21.7: "the prompt also
## surfaces the single weakest-link station's familiarity as a percentage."
## Read as a mastery percentage (how familiar, not how much risk reduction) -
## the doc's wording is ambiguous between the two, this is the more literal
## reading of "familiarity as a percentage."
func weakest_familiarity_percent(geometry_name: String) -> int:
	return roundi(float(weakest_familiarity_stars(geometry_name)) / 5.0 * 100.0)


## Design doc Section 21.6: "the one case where not proceeding makes sense" -
## gated on "very high familiarity," interpreted here as no per-station
## weakness at all (every tracked station at Tier 4+ stars, 80%+) rather than
## requiring a perfect 5/5 sweep - "very high" reads as "expert," not
## necessarily "fully mastered everywhere." First-pass placeholder threshold,
## same spirit as every other invented number in this file.
const SCRAP_FAMILIARITY_THRESHOLD_STARS: int = 4

func can_scrap_for_expertise(part: Part) -> bool:
	if not part.is_defective:
		return false
	return weakest_familiarity_stars(geometry_name_for_part(part)) >= SCRAP_FAMILIARITY_THRESHOLD_STARS


## The only scrap-before-shipping action in the game (design doc Section
## 21.6) - unregisters the part from active_parts (it stops counting toward
## its contract's in-pipeline count and never ships) without touching
## Reputation, since Reputation itself isn't built yet and this is a
## deliberate, informed player choice rather than a quality failure. Only
## removes it from GameData's own bookkeeping - the caller is responsible for
## also removing it from wherever it's physically sitting (a Station's
## current_part/queue_rack/parallel-shelling arrays, or GameData.held_parts) -
## see Station.remove_part().
func scrap_part_for_expertise(part: Part) -> bool:
	if not can_scrap_for_expertise(part):
		return false
	unregister_part(part)
	return true


func _clear_defect_and_raise_familiarity(part: Part, stars: int) -> void:
	raise_familiarity(geometry_name_for_part(part), part.defect_station_id, stars)
	part.clear_defect()


## Whether any hired specialist covers category (design doc Section 9's
## specialist table) - checked in Station._roll_defect_outcome() as a 50%
## post-roll suppression chance on top of the normal risk math.
func has_specialist_for(category: DefectCategory) -> bool:
	for type in specialists_hired:
		if SPECIALIST_CATEGORIES.get(type, []).has(category):
			return true
	return false


func is_specialist_hired(type: SpecialistType) -> bool:
	return specialists_hired.has(type)


## Hires a specialist (one-time cost, no ongoing wage) if not already on
## staff and affordable, then immediately resolves every currently-flagged
## Part whose category this specialist covers - Section 9 groups "bring in a
## specialist" as one of the three ways to fix an existing defect, not just a
## standing future discount, and each resolution raises that Part's
## contract's geometry familiarity same as a "resolved specialist visit"
## should. Returns whether the hire happened.
func hire_specialist(type: SpecialistType) -> bool:
	if is_specialist_hired(type):
		return false
	if not try_spend_with_gems(SPECIALIST_HIRE_COST):
		return false
	specialists_hired.append(type)
	var categories: Array = SPECIALIST_CATEGORIES.get(type, [])
	for part in active_parts:
		if not part.is_defective or not categories.has(part.defect_category):
			continue
		if nc_shelf.has(part):
			# On the NC shelf (design doc 28.3) a specialist's expertise counts
			# as the diagnosis - the player still chooses the disposition.
			if not part.nc_diagnosed:
				part.nc_diagnosed = true
				raise_familiarity(geometry_name_for_part(part), part.defect_station_id, FAMILIARITY_GAIN_SPECIALIST)
		else:
			_clear_defect_and_raise_familiarity(part, FAMILIARITY_GAIN_SPECIALIST)
	nc_shelf_changed.emit()
	return true


## Section 9's first fix path: "quick, cheap, and reliable... it is a patch,
## not a fix, so it does not build familiarity, since the underlying cause
## was never addressed." Shell Crack only, per the doc.
func can_mortar_patch(part: Part) -> bool:
	return part.is_defective and part.defect_category == DefectCategory.SHELL_CRACK


## Spends currency and clears the flag with NO familiarity gain - see
## can_mortar_patch()'s comment for why. Returns whether it happened.
func mortar_patch_defect(part: Part) -> bool:
	if not can_mortar_patch(part):
		return false
	if not try_spend_with_gems(MORTAR_PATCH_COST):
		return false
	part.clear_defect()
	return true


## Section 9's second fix path: "spend time and money adjusting the
## geometry... this is what raises familiarity." Works on any defect
## category, unlike a mortar patch. Returns whether it happened.
func redesign_defect(part: Part) -> bool:
	if not part.is_defective:
		return false
	if not try_spend_with_gems(REDESIGN_COST):
		return false
	_clear_defect_and_raise_familiarity(part, FAMILIARITY_GAIN_REDESIGN)
	return true


## Picks one of station_id's candidate defect categories at random (even
## odds - see STATION_DEFECT_CATEGORIES above), or DefectCategory.NONE if
## this station has none listed.
func roll_defect_category(station_id: String) -> DefectCategory:
	var candidates: Array = STATION_DEFECT_CATEGORIES.get(defect_table_key(station_id), [])
	if candidates.is_empty():
		return DefectCategory.NONE
	return candidates[randi() % candidates.size()]


## Prototype-scale seconds, same conversion as StationDef.get_prototype_timer_seconds().
func grace_period_seconds_for(station_id: String) -> float:
	return game_minutes_to_seconds(STATION_GRACE_PERIOD_MINUTES.get(defect_table_key(station_id), 0.0))


# =========================================================================
# Persistence (save/load)
# =========================================================================
#
# GameData owns "what my state is, as a plain Dictionary"; SaveManager owns
# the file itself, the autosave cadence, and offline catch-up. Split that way
# so this file doesn't also grow file I/O, and so a test can round-trip state
# through a dict without touching the disk.
#
# Object identity is the whole difficulty here. A Part is referenced by
# active_parts, held_parts, a Station's current_part/queue_rack/shelling runs,
# and a Technician's carried_parts - all pointing at ONE instance. So the Part
# is serialized exactly once (in active_parts) and every other holder stores a
# part_id; load rebuilds the parts first, then hands a part_id -> Part map to
# each holder. Technicians work the same way, keyed by index into technicians.

## Bumped only if a future change makes an older file unreadable; load_from_dict()
## refuses a file from the future rather than misreading it.
const SAVE_FORMAT_VERSION: int = 1


func to_save_dict() -> Dictionary:
	# Technician -> index, so stations can reference workers without copying them.
	var tech_indices := {}
	for i in technicians.size():
		tech_indices[technicians[i]] = i

	var parts_data: Array = []
	for part in active_parts:
		parts_data.append(part.to_dict())

	var held_ids: Array = []
	for part in held_parts:
		held_ids.append(part.part_id)

	var contracts_data: Array = []
	for c in contracts:
		contracts_data.append(c.to_dict())

	var offers_data: Array = []
	for c in contract_offers:
		offers_data.append(c.to_dict())

	var techs_data: Array = []
	for tech in technicians:
		techs_data.append(tech.to_dict())

	var applicants_data: Array = []
	for applicant in applicant_pool:
		applicants_data.append(applicant.to_dict())

	var specialists_data: Array = []
	for specialist in specialists_hired:
		specialists_data.append(int(specialist))

	var stations_data := {}
	for station_id in station_by_id:
		var station: Station = station_by_id[station_id]
		stations_data[station_id] = station.to_save_dict(tech_indices)

	return {
		"format_version": SAVE_FORMAT_VERSION,
		"currency": currency,
		"gems": gems,
		"reputation": reputation,
		"factory_level": factory_level,
		"factory_exp": factory_exp,
		"owned_printer_count": owned_printer_count,
		"geometry_familiarity": geometry_familiarity.duplicate(true),
		"company_relationships": company_relationships.duplicate(true),
		"specialists_hired": specialists_data,
		"contract_generation_cooldown": _contract_generation_cooldown,
		"applicant_pool_cooldown": _applicant_pool_cooldown,
		"next_part_id": Part.peek_next_id(),
		"next_contract_id": Contract.peek_next_id(),
		"active_parts": parts_data,
		"held_part_ids": held_ids,
		"contracts": contracts_data,
		"contract_offers": offers_data,
		"technicians": techs_data,
		"applicant_pool": applicants_data,
		"stations": stations_data,
		"station_stats": station_stats.duplicate(true),
		"nc_shelf_ids": nc_shelf.map(func(p: Part): return p.part_id),
		"revert_stock": revert_stock,
		"print_orders": print_orders.duplicate(true),
		"pending_trial_fixes": pending_trial_fixes.keys().map(func(id): return {"contract_id": id, "fix": pending_trial_fixes[id]}),
		"scrapped_part_count": scrapped_part_count,
		"stats_elapsed": stats_elapsed,
	}


## Returns false (changing nothing) if the file is from a newer format version
## than this build understands - better to start a fresh game than to load a
## save wrong and corrupt it on the next write.
##
## Ordering matters and is the reason this reads top-to-bottom the way it does:
## parts must exist before anything that references them by id, and technicians
## before the stations that reference them by index.
func load_from_dict(data: Dictionary) -> bool:
	var version := int(data.get("format_version", 0))
	if version > SAVE_FORMAT_VERSION:
		push_warning("Save file format %d is newer than this build's %d - ignoring it." % [
			version, SAVE_FORMAT_VERSION])
		return false

	currency = int(data.get("currency", currency))
	gems = int(data.get("gems", gems))
	reputation = int(data.get("reputation", reputation))
	factory_level = int(data.get("factory_level", factory_level))
	factory_exp = int(data.get("factory_exp", factory_exp))
	owned_printer_count = int(data.get("owned_printer_count", owned_printer_count))
	_contract_generation_cooldown = float(data.get("contract_generation_cooldown", 0.0))
	_applicant_pool_cooldown = float(data.get("applicant_pool_cooldown", 0.0))

	# Star counts are ints everywhere they're compared/incremented, but JSON
	# hands every number back as a float - coerce rather than storing 3.0.
	geometry_familiarity = {}
	for geometry in data.get("geometry_familiarity", {}):
		var per_station := {}
		for station_id in data["geometry_familiarity"][geometry]:
			per_station[str(station_id)] = int(data["geometry_familiarity"][geometry][station_id])
		geometry_familiarity[str(geometry)] = per_station

	# Relationships are genuinely fractional (RELATIONSHIP_LOSS_MISSED_DEADLINE
	# is 1.5), so these stay floats.
	# Saves from before the stats collector simply start counting from zero.
	station_stats = {}
	var saved_stats: Dictionary = data.get("station_stats", {})
	for station_id in saved_stats:
		var entry: Dictionary = saved_stats[station_id]
		station_stats[str(station_id)] = {
			"completed": int(entry.get("completed", 0)),
			"flagged": int(entry.get("flagged", 0)),
			"cycle_total": float(entry.get("cycle_total", 0.0)),
			"busy": float(entry.get("busy", 0.0)),
		}
	stats_elapsed = float(data.get("stats_elapsed", 0.0))
	company_relationships = {}
	for customer in data.get("company_relationships", {}):
		company_relationships[str(customer)] = float(data["company_relationships"][customer])

	specialists_hired.clear()
	for raw in data.get("specialists_hired", []):
		specialists_hired.append(int(raw) as SpecialistType)

	# --- parts first: everything below references them by id ---
	active_parts.clear()
	var parts_by_id := {}
	for raw in data.get("active_parts", []):
		var part := Part.from_dict(raw)
		active_parts.append(part)
		parts_by_id[part.part_id] = part

	held_parts.clear()
	for raw_id in data.get("held_part_ids", []):
		var part: Part = parts_by_id.get(int(raw_id))
		if part != null:
			held_parts.append(part)

	nc_shelf.clear()
	for raw_id in data.get("nc_shelf_ids", []):
		var part: Part = parts_by_id.get(int(raw_id))
		if part != null:
			nc_shelf.append(part)
	scrapped_part_count = int(data.get("scrapped_part_count", 0))
	revert_stock = int(data.get("revert_stock", STARTING_REVERT_STOCK))
	print_orders.clear()
	for raw in data.get("print_orders", []):
		print_orders.append({
			"contract_id": int(raw.get("contract_id", -1)),
			"line_item_index": int(raw.get("line_item_index", 0)),
			"is_trial": bool(raw.get("is_trial", false)),
			"fix_station_id": str(raw.get("fix_station_id", "")),
			"fix_risk_mult": float(raw.get("fix_risk_mult", 1.0)),
		})
	pending_trial_fixes.clear()
	for raw in data.get("pending_trial_fixes", []):
		var fix: Dictionary = raw.get("fix", {})
		pending_trial_fixes[int(raw.get("contract_id", -1))] = {
			"station_id": str(fix.get("station_id", "")),
			"risk_mult": float(fix.get("risk_mult", 1.0)),
			"uses_left": int(fix.get("uses_left", 0)),
		}

	contracts.clear()
	for raw in data.get("contracts", []):
		contracts.append(Contract.from_dict(raw))

	contract_offers.clear()
	for raw in data.get("contract_offers", []):
		contract_offers.append(Contract.from_dict(raw))

	# --- technicians before stations, which reference them by index ---
	var tech_dicts: Array = data.get("technicians", [])
	technicians.clear()
	for raw in tech_dicts:
		technicians.append(Technician.from_dict(raw))
	# Second pass for carried_parts, now that every Part exists.
	for i in technicians.size():
		technicians[i].restore_carried_parts(tech_dicts[i], parts_by_id)

	applicant_pool.clear()
	for raw in data.get("applicant_pool", []):
		applicant_pool.append(Technician.from_dict(raw))

	# Restore the id counters AFTER rebuilding, since every Part.new()/
	# Contract.new() above consumed an id off them.
	Part.set_next_id(int(data.get("next_part_id", 1)))
	Contract.set_next_id(int(data.get("next_contract_id", 1)))

	var stations_data: Dictionary = data.get("stations", {})
	for station_id in stations_data:
		var station: Station = station_by_id.get(station_id)
		if station == null:
			# A station id in the file that this build doesn't spawn (e.g. a
			# printer instance saved when owned_printer_count was higher).
			# main.gd spawns printers from owned_printer_count before this runs,
			# so this should only ever hit on a real config change.
			continue
		station.load_save_dict(stations_data[station_id], parts_by_id, technicians)

	# Saves from before design doc 28.2 have Engineers staffing stations; they
	# own contracts now, so take them off the floor.
	for engineer in engineers():
		for station: Station in station_by_id.values():
			station.unassign_technician(engineer)
		engineer.assigned_station_ids.clear()
		for part in engineer.carried_parts:
			held_parts.append(part)
		engineer.carried_parts.clear()
		engineer.current_station_id = ""
		engineer.is_traveling = false

	_emit_all_loaded_signals()
	return true


## Everything reactive in the UI listens to a signal rather than polling, so a
## load has to announce that effectively everything changed at once.
func _emit_all_loaded_signals() -> void:
	currency_changed.emit(currency)
	gems_changed.emit(gems)
	reputation_changed.emit(reputation)
	factory_progress_changed.emit()
	contract_offers_changed.emit()
	held_parts_changed.emit()
	applicant_pool_changed.emit()
	for c in contracts:
		contract_updated.emit(c)
	for tech in technicians:
		technician_updated.emit(tech)
