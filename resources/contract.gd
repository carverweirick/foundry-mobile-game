extends Resource
class_name Contract

## A single job: customer, quantity, deadline, payout (design doc Section 7).
## Geometry/alloy are flavor strings only for now, not a real system yet -
## quantity_required is just a number per this pass's scope.

enum ContractTier { LOCAL_SHOPS = 1, REGIONAL_MANUFACTURERS = 2, INDUSTRIAL_ACCOUNTS = 3, FLAGSHIP = 4 }

const TIER_LABEL := {
	ContractTier.LOCAL_SHOPS: "Local Shops",
	ContractTier.REGIONAL_MANUFACTURERS: "Regional Manufacturers",
	ContractTier.INDUSTRIAL_ACCOUNTS: "Industrial Accounts",
	ContractTier.FLAGSHIP: "Flagship Contracts",
}

static var _next_contract_id: int = 1

## What a Part's contract_id points back to.
var contract_id: int = 0

@export var customer_name: String = ""
@export var tier: ContractTier = ContractTier.LOCAL_SHOPS
@export var geometry_name: String = ""
@export var alloy_name: String = ""
@export var quantity_required: int = 1

## Prototype-scale seconds, counted from start(). Section 7 only gives
## qualitative Generous/Moderate/Tighter/Tight deadlines per tier - these
## are first-pass placeholder durations, same spirit as the Technician
## hire cost/wage numbers. Tune once playtested.
@export var deadline_seconds: float = 0.0
@export var payout: int = 0

var quantity_shipped: int = 0
var _start_time_msec: int = 0

## Design doc Section 8: a missed deadline dings Reputation and the
## customer's relationship exactly once, at the moment it lapses, rather
## than every frame afterward for as long as the contract stays overdue and
## incomplete. Set by GameData._process_contracts().
var deadline_penalty_applied: bool = false

var is_complete: bool:
	get: return quantity_shipped >= quantity_required

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


func start() -> void:
	_start_time_msec = Time.get_ticks_msec()
