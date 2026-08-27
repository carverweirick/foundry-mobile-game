extends Resource
class_name Contract

## A single job: customer, one or more line items, deadline, payout (design
## doc Section 7, extended by Section 24.1). Geometry/alloy are flavor
## strings only for now, not a real system yet.
##
## Multi-line-item contracts (this session, design doc Section 24.1): a
## contract can ask for several different geometries at once - "20 turbine
## blades AND 15 bracket assemblies, one contract, one deadline, one payout."
## A Part belongs to exactly one LineItem (Part.line_item_index), and the
## contract as a whole is only complete once every line item individually
## reaches its own required quantity.

enum ContractTier { LOCAL_SHOPS = 1, REGIONAL_MANUFACTURERS = 2, INDUSTRIAL_ACCOUNTS = 3, FLAGSHIP = 4 }

const TIER_LABEL := {
	ContractTier.LOCAL_SHOPS: "Local Shops",
	ContractTier.REGIONAL_MANUFACTURERS: "Regional Manufacturers",
	ContractTier.INDUSTRIAL_ACCOUNTS: "Industrial Accounts",
	ContractTier.FLAGSHIP: "Flagship Contracts",
}

## One geometry within a contract - its own alloy, quantity, and shipped
## count, tracked independently of every other line item on the same
## contract. Plain inner class (same pattern as Station.ShellingRun), not a
## Resource - never saved/serialized on its own, only ever lives inside its
## parent Contract.
class LineItem:
	var geometry_name: String = ""
	var alloy_name: String = ""
	var quantity_required: int = 1
	var quantity_shipped: int = 0

	var is_complete: bool:
		get: return quantity_shipped >= quantity_required


static var _next_contract_id: int = 1

## What a Part's contract_id points back to.
var contract_id: int = 0

@export var customer_name: String = ""
@export var tier: ContractTier = ContractTier.LOCAL_SHOPS
var line_items: Array[LineItem] = []

## Prototype-scale seconds, counted from start(). Section 7 only gives
## qualitative Generous/Moderate/Tighter/Tight deadlines per tier - these
## are first-pass placeholder durations, same spirit as the Technician
## hire cost/wage numbers. Tune once playtested.
@export var deadline_seconds: float = 0.0
@export var payout: int = 0

var _start_time_msec: int = 0

## Design doc Section 8: a missed deadline dings Reputation and the
## customer's relationship exactly once, at the moment it lapses, rather
## than every frame afterward for as long as the contract stays overdue and
## incomplete. Set by GameData._process_contracts().
var deadline_penalty_applied: bool = false

## Every line item complete - the contract as a whole isn't done until each
## individually rolled ask is fulfilled, not just the total unit count.
var is_complete: bool:
	get:
		for li in line_items:
			if not li.is_complete:
				return false
		return not line_items.is_empty()

## Aggregate totals across every line item - what a single combined progress
## bar/number means for a multi-item contract. Per-line-item detail (what the
## Contract Offers screen shows) reads `line_items` directly instead.
var quantity_required: int:
	get:
		var total := 0
		for li in line_items:
			total += li.quantity_required
		return total

var quantity_shipped: int:
	get:
		var total := 0
		for li in line_items:
			total += li.quantity_shipped
		return total

var time_remaining: float:
	get:
		var elapsed := (Time.get_ticks_msec() - _start_time_msec) / 1000.0
		return max(deadline_seconds - elapsed, 0.0)

var is_overdue: bool:
	get: return time_remaining <= 0.0 and not is_complete

var tier_label: String:
	get: return TIER_LABEL[tier]


func _init() -> void:
	contract_id = _next_contract_id
	_next_contract_id += 1


## Starts the deadline clock. NOT called at construction time any more - an
## offered-but-not-yet-accepted contract (see GameData.contract_offers)
## shouldn't have its deadline silently ticking away before the player ever
## agrees to it. Called by GameData._make_contract() for the six
## immediately-active starting contracts, and by
## GameData.accept_contract_offer() the moment a rolled offer is accepted.
func start() -> void:
	_start_time_msec = Time.get_ticks_msec()


## Null if index is out of range - a Part whose line_item_index somehow
## doesn't resolve (shouldn't happen in practice) degrades to "no geometry
## info" rather than crashing.
func line_item_at(index: int) -> LineItem:
	if index < 0 or index >= line_items.size():
		return null
	return line_items[index]


## The first line item that still has room for more Parts to be created for
## it - shipped-or-in-flight, not just shipped, so this doesn't keep
## overproducing one line item past what's actually needed once enough
## Parts are already somewhere in the pipeline for it. in_flight_counts is
## keyed by line item index, supplied by the caller (GameData already tracks
## active_parts, this class has no reference to that itself). Returns -1 if
## every line item already has enough created.
func first_open_line_item_index(in_flight_counts: Dictionary) -> int:
	for i in line_items.size():
		var li: LineItem = line_items[i]
		var in_flight: int = in_flight_counts.get(i, 0)
		if li.quantity_shipped + in_flight < li.quantity_required:
			return i
	return -1
