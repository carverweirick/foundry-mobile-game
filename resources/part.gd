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
var defect_flagged_at_msec: int = 0
var defect_grace_seconds: float = 0.0
var defect_escalated: bool = false

## Design doc Section 9, "Push Through" - armed by Station.push_through_armed
## (Pour only) the moment this part starts running there; consumed by
## Station._resolve_push_through() when its timer completes. Kept on the
## Part rather than the Station since a station's current_part changes each
## cycle and this only ever applies to the one part it was stamped onto.
var is_push_through: bool = false

var is_defective: bool:
	get: return defect_category != GameData.DefectCategory.NONE

## Seconds left before an unaddressed defect escalates, floored at 0. 0 for
## a Part that isn't currently defective at all.
var defect_time_remaining: float:
	get:
		if not is_defective:
			return 0.0
		var elapsed := (Time.get_ticks_msec() - defect_flagged_at_msec) / 1000.0
		return max(defect_grace_seconds - elapsed, 0.0)


func _init() -> void:
	part_id = _next_part_id
	_next_part_id += 1


## Called by Station._maybe_flag_defect() the moment a risk roll hits.
func flag_defect(category: int, station_id: String, grace_seconds: float) -> void:
	defect_category = category
	defect_station_id = station_id
	defect_flagged_at_msec = Time.get_ticks_msec()
	defect_grace_seconds = grace_seconds
	defect_escalated = false


## Resolves a flagged defect via any of the three fix paths (design doc
## Section 9). Whether this also raises geometry familiarity depends on
## which path called it - a mortar patch never does (see
## GameData.mortar_patch_defect()'s comment), a redesign or a resolved
## specialist visit always does - so the familiarity bump itself lives in
## GameData, not here; this just clears the flag itself.
func clear_defect() -> void:
	defect_category = GameData.DefectCategory.NONE
	defect_station_id = ""
	defect_flagged_at_msec = 0
	defect_grace_seconds = 0.0
	defect_escalated = false
