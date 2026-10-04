extends OverlayBase
class_name NcOverlay

## The nonconformance shelf's menu (design doc 28.1-28.3), opened by tapping
## the shelf in VIM Bay or from the Attention button - the "Quarantine Rack"
## style of the user's mockup (assets/inspo/UI/nc_UI.png). One card per
## quarantined part, its left-hand state color telling the story at a
## glance: gold = waiting for an Engineer, blue = being diagnosed (with a
## live progress bar), green = diagnosed, ready for a decision. Dispositions:
##   Scrap            - always (learn nothing)
##   Rework at <X>    - diagnosed, and the defect is repairable (learning only)
##   Scan to learn    - diagnosed, and the defect isn't repairable
## Cards are rebuilt only when the shelf itself changes (nc_shelf_changed);
## status lines and progress bars update in place on a poll so nothing pops.

const REFRESH_INTERVAL: float = 0.5
const ACTION_COLUMN_WIDTH: float = 96.0

@onready var content: VBoxContainer = %Content

var _intro_label: Label
var _rows: Array[Dictionary] = [] # {part, box, status_icon, status_label, progress, diagnosed}
var _refresh_elapsed: float = 0.0
var _needs_rebuild: bool = true


func _on_ready() -> void:
	content.add_theme_constant_override("separation", 5)
	content.add_child(UiKit.section("Quarantine Rack", "st_warning"))
	var warning := UiKit.card("bad")
	content.add_child(warning)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	warning.add_child(line)
	var icon := UiKit.icon("st_warning")
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(icon)
	_intro_label = UiKit.label("", UiKit.FONT_SMALL)
	_intro_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_intro_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(_intro_label)
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
		_update_row(row)


func _rebuild() -> void:
	for row in _rows:
		MenuLayout.remove_and_free(row.box)
	_rows.clear()

	if GameData.nc_shelf.is_empty():
		_intro_label.text = "The shelf is empty. Any part that picks up a defect is pulled off the line and lands here."
		return
	_intro_label.text = "Undiagnosed parts raise the defect risk at the station that made them. Each contract's Engineer diagnoses its parts; scrap is always available."
	for part in GameData.nc_shelf:
		_rows.append(_build_row(part))


func _build_row(part: Part) -> Dictionary:
	var row := {"part": part, "diagnosed": part.nc_diagnosed}
	var box := UiKit.card(_state_color(part))
	row.box = box
	content.add_child(box)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	box.add_child(line)
	line.add_child(UiKit.framed_icon(UiKit.part_icon(GameData.geometry_name_for_part(part)), 28))

	# Every line single and clipped: the card's height never changes while
	# it's on screen (UI rules 1 and 3); the card's tooltip has it all.
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(info)
	var contract := GameData.get_contract(part.contract_id)
	var origin: Station = GameData.station_by_id.get(part.defect_station_id)
	var origin_name: String = origin.station_name if origin != null else part.defect_station_id
	var title := UiKit.label("Part #%d - %s" % [part.part_id, GameData.geometry_name_for_part(part)], UiKit.FONT_BODY, "header_text")
	title.clip_text = true
	info.add_child(title)
	var source := UiKit.label("For %s" % (contract.customer_name if contract != null else "no contract"), UiKit.FONT_SMALL, "text_dim")
	source.clip_text = true
	info.add_child(source)
	var defect := UiKit.label("%s from %s" % [GameData.DEFECT_CATEGORY_LABEL[part.defect_category], origin_name], UiKit.FONT_SMALL, "bad")
	defect.clip_text = true
	info.add_child(defect)
	var status := HBoxContainer.new()
	status.add_theme_constant_override("separation", 3)
	info.add_child(status)
	row.status_icon = UiKit.icon("st_hourglass")
	status.add_child(row.status_icon)
	row.status_label = UiKit.label("", UiKit.FONT_SMALL)
	row.status_label.clip_text = true
	row.status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	status.add_child(row.status_label)
	row.progress = UiKit.bar("info", 5)
	info.add_child(row.progress)

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 3)
	actions.custom_minimum_size.x = ACTION_COLUMN_WIDTH
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(actions)
	_add_action(actions, "Scrap", "act_scrap", "danger",
		"Scrap the part. You learn nothing from it, and an undiagnosed defect keeps raising risk.",
		func(): GameData.scrap_nc_part(part))
	if part.nc_diagnosed:
		var rework_at := GameData.rework_station_for(part)
		if rework_at != "":
			var station_name: String = GameData.get_station(rework_at).display_name
			_add_action(actions, "Rework at\n%s" % station_name, "act_rework", "warn",
				"Back onto the line to be repaired at %s and learned from. Learning only - it won't ship." % station_name,
				func(): GameData.rework_nc_part(part))
		else:
			_add_action(actions, "Scan to learn", "act_scan", "go",
				"Can't be repaired. Send it to Structured Light Scan to learn from, then it's retired.",
				func(): GameData.scan_nc_part(part))
	box.tooltip_text = "Part #%d - %s\n%s from %s" % [part.part_id, GameData.geometry_name_for_part(part),
		GameData.DEFECT_CATEGORY_LABEL[part.defect_category], origin_name]
	return row


func _add_action(column: VBoxContainer, text: String, icon_name: String, kind: String, tooltip: String, action: Callable) -> void:
	var button := UiKit.button(text, icon_name, kind)
	button.tooltip_text = UiText.tip(tooltip)
	button.pressed.connect(func():
		action.call()
		_needs_rebuild = true
		_refresh.call_deferred())
	column.add_child(button)


func _state_color(part: Part) -> String:
	if part.nc_diagnosed:
		return "good"
	var engineer := GameData.engineer_for_contract(part.contract_id)
	if engineer != null and GameData.diagnosis_target_for(engineer) == part:
		return "info" # engineer blue, as in Team
	return "gold"


func _update_row(row: Dictionary) -> void:
	var part: Part = row.part
	if part.nc_diagnosed != row.diagnosed:
		# Diagnosis finished: the buttons change, so rebuild next refresh.
		_needs_rebuild = true
	UiKit.set_card_border(row.box, _state_color(part))
	var progress: ProgressBar = row.progress
	progress.modulate.a = 0.0
	if part.nc_diagnosed:
		row.status_icon.texture = UiIcons.get_icon("st_check")
		row.status_label.text = "Diagnosed - choose what to do with it"
		return
	var engineer := GameData.engineer_for_contract(part.contract_id)
	if engineer == null:
		row.status_icon.texture = UiIcons.get_icon("st_hourglass")
		row.status_label.text = "Waiting - hire an Engineer in Team" if GameData.engineers().is_empty() else "Waiting - assign an Engineer in Contracts"
		return
	var total := GameData.diagnosis_seconds_for(engineer)
	if GameData.diagnosis_target_for(engineer) == part:
		row.status_icon.texture = UiIcons.get_icon("role_engineer")
		var left := maxf(total - part.nc_diagnosis_elapsed, 0.0)
		row.status_label.text = "%s diagnosing - %ds" % [engineer.technician_name, ceili(left)]
		progress.modulate.a = 1.0
		progress.value = clampf(part.nc_diagnosis_elapsed / maxf(total, 0.01), 0.0, 1.0)
		return
	row.status_icon.texture = UiIcons.get_icon("st_hourglass")
	row.status_label.text = "Queued for %s" % engineer.technician_name
