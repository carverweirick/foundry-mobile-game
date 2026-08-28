extends Node

signal currency_changed(new_amount: int)
signal contract_updated(contract: Contract)
## A new rolled offer joined contract_offers, or one was removed by
## acceptance - the Contract Offers screen listens for this rather than
## polling contract_offers.size() every frame.
signal contract_offers_changed()
signal held_parts_changed()
signal technician_updated(tech: Technician)
signal reputation_changed(new_amount: int)
## Fires whenever factory_exp changes, and again (in addition) whenever that
## pushes factory_level up - PrintersOverlay listens for this the same way
## it already listens for currency_changed, since factory progress doesn't
## otherwise correlate with any existing signal.
signal factory_progress_changed()

## Tier 1 numbers for every station, pulled from the design doc's
## "Starting Timer and Batch Numbers" and "Station Mechanics" sections.
## Tier 2-5 progressions aren't modeled yet, only current_tier's sprite swap is.

## Real per-station minutes are compressed for prototyping (15 real min -> 5s),
## matching the ratio the original PrintingStation prototype used.
const PROTOTYPE_SECONDS_PER_MINUTE: float = 1.0 / 3.0
const MIN_TIMER_SECONDS: float = 2.0

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
const STATION_BASE_DEFECT_RISK := {
	"printing": 0.05,
	"shelling": 0.20,
	"burnout": 0.15,
	"pour": 0.20,
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
const STATION_DEFECT_CATEGORIES := {
	"printing": [DefectCategory.WARPING],
	"shelling": [DefectCategory.SHELL_CRACK],
	"burnout": [DefectCategory.WARPING, DefectCategory.SHELL_CRACK],
	"pour": [DefectCategory.POROSITY, DefectCategory.MISRUN],
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
}

## Familiarity star (0-5) -> risk multiplier, Section 9's table. 5 stars
## floors at 10%, never zero - "genuinely risky early, genuinely safe once
## mastered."
const FAMILIARITY_MULTIPLIER: Array[float] = [1.0, 0.8, 0.6, 0.4, 0.2, 0.1]

## Per-part rolling chance used when an ignored defect escalates (Section 9:
## "a rolling chance the other parts pick up the same issue"). The doc gives
## no concrete number - this is a first-pass placeholder, same spirit as the
## Technician hire costs and contract payouts invented elsewhere.
const DEFECT_CONTAMINATION_CHANCE: float = 0.25

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
		return max(tier1_timer_minutes * PROTOTYPE_SECONDS_PER_MINUTE, MIN_TIMER_SECONDS)


## Placeholder economy: no alloy stock or contract payouts yet, just a
## simple number so hiring has something to spend. Real economy later.
var currency: int = 500

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
const PIPELINE_ORDER: Array[String] = [
	"printing", "clean", "uv_cure", "scan", "patching", "pour_cup_attach",
	"shelling", "burnout", "mold_prep", "pour", "deshell", "abrasive_blast", "ship",
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

## station_id -> live Station node, set by main.gd right after spawning all
## 11 stations (same pattern as every overlay's own station_by_id).
## Technician.tick() needs this to look up real station positions for actual
## distance-based walking - see Technician.WALK_SPEED.
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
## Station.is_parallel_shelling()/shelling_active_parts. No concrete tier
## thresholds given - first-pass placeholder, one extra parallel slot per tier
## starting at Tier 2.
const SHELLING_TIER_PARALLEL_CAP := {1: 1, 2: 2, 3: 3, 4: 4, 5: 5}


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
const CONTRACT_DEADLINE_SECONDS := {
	Contract.ContractTier.LOCAL_SHOPS: 1200.0,
	Contract.ContractTier.REGIONAL_MANUFACTURERS: 1800.0,
	Contract.ContractTier.INDUSTRIAL_ACCOUNTS: 2700.0,
	Contract.ContractTier.FLAGSHIP: 5400.0,
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


func upgrade_cost_for_tier(target_tier: int) -> int:
	if target_tier < 0 or target_tier >= STATION_TIER_UPGRADE_COST.size():
		return 0
	return STATION_TIER_UPGRADE_COST[target_tier]


func rack_upgrade_cost_for(target_capacity: int) -> int:
	if target_capacity < 0 or target_capacity >= STATION_RACK_UPGRADE_COST.size():
		return 0
	return STATION_RACK_UPGRADE_COST[target_capacity]


## Shared spend path: deducts and emits only if affordable. Returns whether
## the spend happened.
func try_spend(amount: int) -> bool:
	if not can_afford(amount):
		return false
	currency -= amount
	currency_changed.emit(currency)
	return true


func register_part(part: Part) -> void:
	active_parts.append(part)


func unregister_part(part: Part) -> void:
	active_parts.erase(part)


func count_parts_in_pipeline(contract_id: int) -> int:
	var count := 0
	for p in active_parts:
		if p.contract_id == contract_id:
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
		if p.contract_id == contract_id:
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
	var deadline: float = CONTRACT_DEADLINE_SECONDS[tier]

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


## Deducts hire_cost, adds the new Technician to the roster, and returns it -
## or null if currency is short. This only hires; assigning them to a
## station (or several) is a separate step, see assign_technician() below.
func hire_technician(tier: Technician.SkillTier, technician_name: String = "") -> Technician:
	var tech := Technician.new()
	tech.skill_tier = tier
	tech.technician_name = technician_name if technician_name != "" else Technician.TIER_LABEL[tier]

	if not try_spend(tech.hire_cost):
		return null

	technicians.append(tech)
	return tech


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
	if station.assigned_technicians.has(tech):
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


## Design request, this session: coordination for multiple technicians
## assigned to the same station - see Technician._priority_tier_for()'s own
## comment for the full rule this supports. Distance is measured against
## whichever concrete station currently sits at station_id in station_by_id;
## returns INF if none found or no other technician is assigned there.
func closest_assigned_technician_distance(station_id: String, excluding: Technician) -> float:
	var station: Station = station_by_id.get(station_id)
	if station == null:
		return INF
	var closest := INF
	for tech in technicians:
		if tech == excluding:
			continue
		if not tech.real_assigned_station_ids().has(station_id):
			continue
		closest = min(closest, tech.current_position.distance_to(station.position))
	return closest


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
func _process(delta: float) -> void:
	for tech in technicians:
		if tech.tick(delta, station_by_id):
			technician_updated.emit(tech)
	_check_defect_escalations()
	_process_contracts(delta)


## Design doc Section 9, escalation: sweeps every live Part (wherever it
## currently sits - a station, a rack, Awaiting Transfer, or a technician's
## hands, active_parts covers all of them) for one whose grace period has
## lapsed unaddressed, and escalates it exactly once. Centralized here rather
## than on Station, since a flagged Part's grace period keeps counting down
## no matter where it physically moves to after being flagged - it's the
## Part's problem now, not something tied to standing at one station.
func _check_defect_escalations() -> void:
	for part in active_parts:
		if not part.is_defective or part.defect_escalated:
			continue
		if part.defect_time_remaining > 0.0:
			continue
		_escalate_defect(part)


## Point 1 of Section 9's escalation: "a rolling chance the other parts pick
## up the same issue." "The rest of that batch" is interpreted as whoever
## else is currently sitting in the station's queue_rack (plus current_part,
## if a different Part has already cycled into the active slot since this
## one was flagged) - the closest existing analog to a batch, since real
## simultaneous multi-part batching (Section 4/17) isn't built. Point 2, the
## reputation hit and the part not counting toward its contract, is handled
## at the moment of shipping instead - see Station._ship_part() - since
## that's specifically what Section 9 describes ("if it ships anyway, or
## sits long enough that it ships"), not the escalation moment itself.
## Reputation itself is stubbed - see the note in _ship_part().
func _escalate_defect(part: Part) -> void:
	part.defect_escalated = true
	var station: Station = station_by_id.get(part.defect_station_id)
	if station == null:
		return
	var batchmates: Array[Part] = station.queue_rack.duplicate()
	if station.current_part != null and station.current_part != part:
		batchmates.append(station.current_part)
	# Parallel shelling (design doc Section 21.4) can have several Parts
	# simultaneously mid-run or simultaneously ready, none of which are
	# station.current_part (always null there) - include them too, same
	# "closest existing analog to a batch" spirit as queue_rack/current_part
	# above.
	if station.is_parallel_shelling():
		for run in station.shelling_active_parts:
			if run.part != part:
				batchmates.append(run.part)
		for other_part in station.shelling_ready_parts:
			if other_part != part:
				batchmates.append(other_part)
	var grace_seconds := grace_period_seconds_for(part.defect_station_id)
	for other in batchmates:
		if other.is_defective:
			continue
		if randf() < DEFECT_CONTAMINATION_CHANCE:
			other.flag_defect(part.defect_category, part.defect_station_id, grace_seconds)


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
		# 20 min/coat * 8 coats required at Tier 1, still one combined timer at
		# Tier 1 specifically.
		StationDef.new("shelling", "Shelling", Station.StationType.QUEUE,
			2, "Shell Building", 160.0, 1),

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
	contracts = [
		_make_single_item_contract("Local Hardware Co.", Contract.ContractTier.LOCAL_SHOPS,
			"Mounting Brackets", "Mild Steel", 5, 1200.0, 50),
		_make_single_item_contract("Riverside Jewelers", Contract.ContractTier.LOCAL_SHOPS,
			"Pendant Blanks", "Bronze", 8, 1200.0, 70),
		_make_single_item_contract("Cascade Fluid Systems", Contract.ContractTier.REGIONAL_MANUFACTURERS,
			"Valve Bodies", "Stainless Steel", 15, 1800.0, 220),
		_make_single_item_contract("Northline Pumps Inc.", Contract.ContractTier.REGIONAL_MANUFACTURERS,
			"Pump Housings", "Cast Iron Blend", 20, 1800.0, 280),
		_make_single_item_contract("Summit Industrial Group", Contract.ContractTier.INDUSTRIAL_ACCOUNTS,
			"Gear Housings", "Alloy Steel", 40, 2700.0, 650),
		# Recurring flagship work isn't modeled yet - this is a one-time
		# contract for now, same as the other five.
		_make_single_item_contract("Meridian Aerospace", Contract.ContractTier.FLAGSHIP,
			"Turbine Blades", "Nickel Superalloy", 120, 5400.0, 2500),
	]


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
## below) - builds the one-element line_items array _make_contract() now
## expects, so those call sites don't need to construct a LineItem by hand.
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
	return _make_contract(customer, tier, items, deadline_seconds, payout, true)


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


## Design request (this session): "i want you to gain exp from completing
## contracts. no currency to upgrade factory level" - Factory Level now
## rises purely from a lifetime EXP total awarded whenever a contract fully
## ships, never spent and with no currency step at all (unlike literally
## every other upgrade in the game - stations, printers, rack capacity,
## specialists, technicians). This directly answers design doc Section 20
## item 5 ("decide what actually raises factory level").
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
## Reputation itself uses. A single big contract can cross more than one
## level's threshold at once, so this loops rather than checking once.
func _award_factory_exp(tier: Contract.ContractTier) -> void:
	factory_exp += FACTORY_EXP_PER_CONTRACT_TIER.get(tier, FACTORY_EXP_PER_CONTRACT_TIER[Contract.ContractTier.LOCAL_SHOPS])
	while not is_factory_level_maxed() and factory_exp >= factory_exp_for_level(factory_level + 1):
		factory_level += 1
	factory_progress_changed.emit()


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
	if not try_spend(printer_purchase_cost()):
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
## (StaffOverlay's technician assignment checkboxes, OverviewOverlay's list)
## uses this instead of PIPELINE_ORDER directly.
func all_real_station_ids() -> Array[String]:
	var ids := printer_station_ids()
	for id in PIPELINE_ORDER:
		if id != "printing":
			ids.append(id)
	return ids


## 0.0 (no roll ever happens) for any station not in STATION_BASE_DEFECT_RISK.
func base_defect_risk_for(station_id: String) -> float:
	return STATION_BASE_DEFECT_RISK.get(station_id, 0.0)


## 0 for any geometry/station pair never raised, or for any station_id not in
## FAMILIARITY_TRACKED_STATIONS (Printing included - see the field comment above).
func familiarity_stars_for(geometry_name: String, station_id: String) -> int:
	var per_station: Dictionary = geometry_familiarity.get(geometry_name, {})
	return per_station.get(station_id, 0)


## 1.0 (no reduction at all) for any station_id not in
## FAMILIARITY_TRACKED_STATIONS, so Station._roll_defect_outcome() can call
## this unconditionally for every defect-rolling station (Printing included)
## without special-casing which ones actually track familiarity.
func familiarity_multiplier_for(geometry_name: String, station_id: String) -> float:
	if not FAMILIARITY_TRACKED_STATIONS.has(station_id):
		return 1.0
	return FAMILIARITY_MULTIPLIER[familiarity_stars_for(geometry_name, station_id)]


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


## Quick-glance summary (design doc Section 21.7): a single average across
## every tracked station, as a star rating - "same visual language as the old
## single score." Rounded to the nearest whole star for display; callers that
## want the raw fractional average (e.g. for a half-star icon later) can
## still read FAMILIARITY_TRACKED_STATIONS + familiarity_stars_for() directly.
func average_familiarity_stars(geometry_name: String) -> int:
	var total := 0
	for station_id in FAMILIARITY_TRACKED_STATIONS:
		total += familiarity_stars_for(geometry_name, station_id)
	return roundi(float(total) / FAMILIARITY_TRACKED_STATIONS.size())


## The single lowest per-station star rating for this geometry - design doc
## Section 21.7: "an average could otherwise hide a real problem area."
func weakest_familiarity_stars(geometry_name: String) -> int:
	var weakest := 5
	for station_id in FAMILIARITY_TRACKED_STATIONS:
		weakest = min(weakest, familiarity_stars_for(geometry_name, station_id))
	return weakest


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
	if not try_spend(SPECIALIST_HIRE_COST):
		return false
	specialists_hired.append(type)
	var categories: Array = SPECIALIST_CATEGORIES.get(type, [])
	for part in active_parts:
		if part.is_defective and categories.has(part.defect_category):
			_clear_defect_and_raise_familiarity(part, FAMILIARITY_GAIN_SPECIALIST)
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
	if not try_spend(MORTAR_PATCH_COST):
		return false
	part.clear_defect()
	return true


## Section 9's second fix path: "spend time and money adjusting the
## geometry... this is what raises familiarity." Works on any defect
## category, unlike a mortar patch. Returns whether it happened.
func redesign_defect(part: Part) -> bool:
	if not part.is_defective:
		return false
	if not try_spend(REDESIGN_COST):
		return false
	_clear_defect_and_raise_familiarity(part, FAMILIARITY_GAIN_REDESIGN)
	return true


## Picks one of station_id's candidate defect categories at random (even
## odds - see STATION_DEFECT_CATEGORIES above), or DefectCategory.NONE if
## this station has none listed.
func roll_defect_category(station_id: String) -> DefectCategory:
	var candidates: Array = STATION_DEFECT_CATEGORIES.get(station_id, [])
	if candidates.is_empty():
		return DefectCategory.NONE
	return candidates[randi() % candidates.size()]


## Prototype-scale seconds, same conversion as StationDef.get_prototype_timer_seconds().
func grace_period_seconds_for(station_id: String) -> float:
	var minutes: float = STATION_GRACE_PERIOD_MINUTES.get(station_id, 0.0)
	if minutes <= 0.0:
		return 0.0
	return max(minutes * PROTOTYPE_SECONDS_PER_MINUTE, MIN_TIMER_SECONDS)
