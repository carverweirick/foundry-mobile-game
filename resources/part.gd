extends Resource
class_name Part

## A single unit moving through the pipeline (design doc Section 2/3).
## current_station_index is this part's position in GameData.PIPELINE_ORDER,
## advanced by Station.receive_part() each time it's routed forward.

enum Status { IN_STATION, READY_TO_ROUTE, SHIPPED }

static var _next_part_id: int = 1

var part_id: int = 0
var current_station_index: int = 0
var status: Status = Status.IN_STATION
var contract_id: int = -1

## Which of its contract's Contract.line_items this Part actually is (design
## doc Section 24.1, multi-line-item contracts) - a contract can ask for
## several different geometries at once, so a Part needs to know which
## specific one it represents, not just which contract it's for. Set once at
## creation (Station._try_create_part()) and never changes afterward.
var line_item_index: int = 0

## Design doc Section 9 - set by Station._maybe_flag_defect() when a risk
## roll hits. defect_station_id is the station that flagged it (needed to
## know whose queue_rack to contaminate on escalation, and to look up the
## right grace period). defect_escalated guards the one-time escalation
## trigger (contamination roll) once the grace period lapses - see
## GameData._check_defect_escalations(). Cleared via clear_defect() below,
## called by GameData.mortar_patch_defect()/redesign_defect() and a hired
## specialist's auto-resolve pass (GameData.hire_specialist()) - the three
## fix paths from Section 9.
var defect_category: int = 0 # GameData.DefectCategory, default NONE
var defect_station_id: String = ""
## Seconds burned off this defect's grace period so far, advanced by
## GameData.simulate() rather than read off a wall clock. Was
## `defect_flagged_at_msec` + Time.get_ticks_msec() until the save/load work,
## which had the same two problems Contract.elapsed_seconds documents: it
## reset on every launch, and it couldn't be fast-forwarded. An accumulator
## saves and steps cleanly.
var defect_elapsed: float = 0.0
var defect_grace_seconds: float = 0.0
var defect_escalated: bool = false

## Design doc Section 9, "Push Through" - armed by Station.push_through_armed
## (Pour only) the moment this part starts running there; consumed by
## Station._resolve_push_through() when its timer completes. Kept on the
## Part rather than the Station since a station's current_part changes each
## cycle and this only ever applies to the one part it was stamped onto.
var is_push_through: bool = false

## Nonconformance shelf (design doc 28.1-28.3). A part is quarantined on
## GameData.nc_shelf the moment a defect is flagged; its contract's Engineer
## diagnoses it in the background (nc_diagnosis_elapsed counts up to
## GameData.diagnosis_seconds_for()), and only a diagnosed part can be
## reworked or scanned for learning. Scrap is allowed either way.
var nc_diagnosed: bool = false
var nc_diagnosis_elapsed: float = 0.0

## Set by a learning disposition (rework, or scan-to-learn): the part goes
## back onto the line to teach the shop about its geometry but can never
## ship - Station retires it at Ship (or at Scan for scan_to_learn) instead
## of crediting its contract, and it no longer counts as in flight for that
## contract. learning_origin_station_id remembers which station flagged it.
var learning_only: bool = false
var scan_to_learn: bool = false
var learning_origin_station_id: String = ""

var is_defective: bool:
	get: return defect_category != GameData.DefectCategory.NONE

## Seconds left before an unaddressed defect escalates, floored at 0. 0 for
## a Part that isn't currently defective at all.
var defect_time_remaining: float:
	get:
		if not is_defective:
			return 0.0
		return max(defect_grace_seconds - defect_elapsed, 0.0)


func _init() -> void:
	part_id = _next_part_id
	_next_part_id += 1


## Called by Station._maybe_flag_defect() the moment a risk roll hits.
func flag_defect(category: int, station_id: String, grace_seconds: float) -> void:
	defect_category = category
	defect_station_id = station_id
	defect_elapsed = 0.0
	defect_grace_seconds = grace_seconds
	defect_escalated = false


## Resolves a flagged defect via any of the three fix paths (design doc
## Section 9). Whether this also raises geometry familiarity depends on
## which path called it - a mortar patch never does (see
## GameData.mortar_patch_defect()'s comment), a redesign or a resolved
## specialist visit always does - so the familiarity bump itself lives in
## GameData, not here; this just clears the flag itself.
func clear_defect() -> void:
	nc_diagnosed = false
	nc_diagnosis_elapsed = 0.0
	defect_category = GameData.DefectCategory.NONE
	defect_station_id = ""
	defect_elapsed = 0.0
	defect_grace_seconds = 0.0
	defect_escalated = false


# --- Persistence (save/load) ---------------------------------------------
#
# A Part is referenced from several places at once (GameData.active_parts,
# GameData.held_parts, a Station's current_part/queue_rack/shelling runs, a
# Technician's carried_parts). Only GameData.active_parts - the master
# registry every live Part is in from creation to shipment - serializes the
# Part itself; every other holder saves just this part_id and re-resolves the
# shared instance on load. That's what keeps object identity intact instead of
# silently deep-copying one Part into four unrelated ones.


func to_dict() -> Dictionary:
	return {
		"part_id": part_id,
		"current_station_index": current_station_index,
		"status": int(status),
		"contract_id": contract_id,
		"line_item_index": line_item_index,
		"defect_category": defect_category,
		"defect_station_id": defect_station_id,
		"defect_elapsed": defect_elapsed,
		"defect_grace_seconds": defect_grace_seconds,
		"defect_escalated": defect_escalated,
		"is_push_through": is_push_through,
		"nc_diagnosed": nc_diagnosed,
		"nc_diagnosis_elapsed": nc_diagnosis_elapsed,
		"learning_only": learning_only,
		"scan_to_learn": scan_to_learn,
		"learning_origin_station_id": learning_origin_station_id,
	}


static func from_dict(data: Dictionary) -> Part:
	var part := Part.new()
	# _init() already claimed a fresh id off _next_part_id; overwrite it with
	# the saved one. GameData.load_from_dict() restores the counter itself
	# afterward, so later parts keep issuing unused ids.
	part.part_id = int(data.get("part_id", 0))
	part.current_station_index = int(data.get("current_station_index", 0))
	part.status = data.get("status", Status.IN_STATION) as Status
	part.contract_id = int(data.get("contract_id", -1))
	part.line_item_index = int(data.get("line_item_index", 0))
	part.defect_category = int(data.get("defect_category", 0))
	part.defect_station_id = str(data.get("defect_station_id", ""))
	part.defect_elapsed = float(data.get("defect_elapsed", 0.0))
	part.defect_grace_seconds = float(data.get("defect_grace_seconds", 0.0))
	part.defect_escalated = bool(data.get("defect_escalated", false))
	part.is_push_through = bool(data.get("is_push_through", false))
	part.nc_diagnosed = bool(data.get("nc_diagnosed", false))
	part.nc_diagnosis_elapsed = float(data.get("nc_diagnosis_elapsed", 0.0))
	part.learning_only = bool(data.get("learning_only", false))
	part.scan_to_learn = bool(data.get("scan_to_learn", false))
	part.learning_origin_station_id = str(data.get("learning_origin_station_id", ""))
	return part


## Highest id ever issued, so GameData.load_from_dict() can restore the static
## counter and a part created after loading can't collide with a saved one.
static func peek_next_id() -> int:
	return _next_part_id


static func set_next_id(value: int) -> void:
	_next_part_id = max(value, 1)
