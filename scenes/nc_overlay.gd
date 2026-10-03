extends OverlayBase
class_name NcOverlay

## The nonconformance shelf's menu (design doc 28.1-28.3), opened by tapping
## the shelf in VIM Bay or from the Attention button. Lists every
## quarantined part with its defect, where it came from, and its diagnosis
## state, plus the dispositions allowed right now:
##   Scrap            - always (learn nothing)
##   Rework at <X>    - diagnosed, and the defect is repairable (learning only)
##   Scan to learn    - diagnosed, and the defect isn't repairable
## Rows are rebuilt only when the shelf itself changes (nc_shelf_changed);
## the diagnosis countdowns update in place on a poll so nothing "pops".

const REFRESH_INTERVAL: float = 0.5
const HEADER_COLOR := Color(0.85, 0.64, 0.16)
const DEFECT_COLOR := Color(0.88, 0.35, 0.22)

@onready var content: VBoxContainer = %Content

var _intro_label: Label
var _rows: Array[Dictionary] = [] # {part, status_label}
var _refresh_elapsed: float = 0.0
var _needs_rebuild: bool = true


func _on_ready() -> void:
	_intro_label = Label.new()
	_intro_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_intro_label)
	GameData.nc_shelf_changed.connect(func(): _needs_rebuild = true)


func _on_open() -> void:
	_needs_rebuild = true
	_refresh()


func _process(delta: float) -> void:
	if not panel.visible:
		return
	_refresh_elapsed += delta
	if _refresh_elapsed < REFRESH_INTERVAL or _click_in_progress():
		return
	_refresh_elapsed = 0.0
	_refresh()


func _refresh() -> void:
	if _needs_rebuild:
		_needs_rebuild = false
		_rebuild()
	for row in _rows:
		row.status_label.text = _status_text(row.part)


func _rebuild() -> void:
	for row in _rows:
		row.box.queue_free()
	_rows.clear()

	var count := GameData.nc_shelf.size()
	if count == 0:
		_intro_label.text = "The nonconformance shelf is empty. Any part that picks up a defect is pulled off the line and lands here."
		return
	_intro_label.text = "Undiagnosed parts raise the defect risk at the station that made them. Each contract's Engineer diagnoses its parts; scrap is always available."

	for part in GameData.nc_shelf:
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 1)
		content.add_child(box)

		var title := Label.new()
		title.add_theme_color_override("font_color", HEADER_COLOR)
		var contract := GameData.get_contract(part.contract_id)
		title.text = "Part #%d - %s" % [part.part_id, GameData.geometry_name_for_part(part)]
		box.add_child(title)

		var detail := Label.new()
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var origin: Station = GameData.station_by_id.get(part.defect_station_id)
		detail.text = "%s from %s (%s)" % [
			GameData.DEFECT_CATEGORY_LABEL[part.defect_category],
			origin.station_name if origin != null else part.defect_station_id,
			contract.customer_name if contract != null else "no contract",
		]
		detail.add_theme_color_override("font_color", DEFECT_COLOR)
		box.add_child(detail)

		# Variable-length text - a two-line floor stops the rows below
		# reflowing as the countdown changes (CLAUDE.md UI rule 3).
		var status := Label.new()
		status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status.custom_minimum_size = Vector2(0.0, 26.0)
		box.add_child(status)

		# Button count/width varies per part - HFlowContainer (UI rule 2).
		var actions := HFlowContainer.new()
		box.add_child(actions)
		_add_action(actions, "Scrap", "Scrap the part. You learn nothing from it, and an undiagnosed defect keeps raising risk.", func(): GameData.scrap_nc_part(part))
		if part.nc_diagnosed:
			var rework_at := GameData.rework_station_for(part)
			if rework_at != "":
				var station_name: String = GameData.get_station(rework_at).display_name
				_add_action(actions, "Rework at %s" % station_name,
					"Back onto the line to be repaired at %s and learned from. Learning only - it won't ship." % station_name,
					func(): GameData.rework_nc_part(part))
			else:
				_add_action(actions, "Scan to learn",
					"Can't be repaired. Send it to Structured Light Scan to learn from, then it's retired.",
					func(): GameData.scan_nc_part(part))

		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0.0, 4.0)
		box.add_child(spacer)
		_rows.append({"part": part, "status_label": status, "box": box})


func _add_action(row: HFlowContainer, text: String, tooltip: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.pressed.connect(func():
		action.call()
		_needs_rebuild = true
		_refresh.call_deferred())
	row.add_child(button)


func _status_text(part: Part) -> String:
	if part.nc_diagnosed:
		return "Diagnosed - choose what to do with it."
	var engineer := GameData.engineer_for_contract(part.contract_id)
	if engineer == null:
		if GameData.engineers().is_empty():
			return "Waiting - hire an Engineer (Team) to diagnose defects."
		return "Waiting - this contract has no Engineer. Assign one in Contracts."
	var target := GameData.diagnosis_target_for(engineer)
	var left := maxf(GameData.diagnosis_seconds_for(engineer) - part.nc_diagnosis_elapsed, 0.0)
	if target == part:
		return "%s is diagnosing - %ds left" % [engineer.technician_name, ceili(left)]
	return "Queued for %s (busy with another part)" % engineer.technician_name
