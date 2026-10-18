extends OverlayBase
class_name NcOverlay

## The nonconformance shelf's menu (design doc 28.1-28.3), opened by tapping
## the shelf in VIM Bay or from the Attention button - the "Quarantine Rack"
## style of the user's mockup (assets/inspo/UI/nc_UI.png). One card per
## quarantined part, its left-hand state color telling the story at a
## glance: gold = waiting for an Engineer, blue = being diagnosed (with a
## live progress bar), green = diagnosed, ready for a decision. Dispositions:
##   Scrap            - always (learn nothing; a casting gives 1 revert)
##   Rework at <X>    - diagnosed, and the defect is repairable (learning only)
##   Scan to learn    - diagnosed, and the defect isn't repairable
## Each learning button shows the familiarity it's sure to teach
## (GameData.learning_gain_percent()) - what not scrapping the part buys.
## The shelf has two sides (user request, 2026-10-18): the intake side holds
## parts waiting on a decision; Rework/Scan moves a part to the pickup side,
## where a technician collects it and carries it to its next station (Send
## does it by hand). Cards are rebuilt only when the shelf itself changes
## (nc_shelf_changed); status lines and progress bars update in place on a
## poll so nothing pops.

const REFRESH_INTERVAL: float = 0.5
const ACTION_COLUMN_WIDTH: float = 124.0

@onready var content: VBoxContainer = %Content

var _intro_label: Label
var _intake_list: VBoxContainer
var _pickup_section: PanelContainer
var _pickup_hint: Label
var _pickup_list: VBoxContainer
# Intake: {kind, part, box, status_icon, status_label, progress, diagnosed}
# Pickup: {kind, part, box, status_icon, status_label, send}
var _rows: Array[Dictionary] = []
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
	_intake_list = _list()
	_pickup_section = UiKit.section("Pickup Side", "act_send")
	content.add_child(_pickup_section)
	_pickup_hint = UiKit.label("Reworked and scanned parts wait here until a technician carries them back to the line.", UiKit.FONT_SMALL, "text_dim")
	_pickup_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(_pickup_hint)
	_pickup_list = _list()
	GameData.nc_shelf_changed.connect(func(): _needs_rebuild = true)


func _list() -> VBoxContainer:
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 5)
	content.add_child(list)
	return list


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

	var pickups := GameData.nc_pickup.size()
	(_pickup_section.get_meta("right_label") as Label).text = "empty" if pickups == 0 else "%d waiting" % pickups
	_pickup_hint.visible = pickups == 0
	for part in GameData.nc_pickup:
		_rows.append(_build_pickup_row(part))

	if GameData.nc_shelf.is_empty():
		_intro_label.text = "Nothing waiting on a decision. Any part that picks up a defect is pulled off the line and lands here."
		return
	_intro_label.text = "Undiagnosed parts raise the defect risk at the station that made them. Scrap a casting for revert, or rework or scan it for the familiarity shown."
	for part in GameData.nc_shelf:
		_rows.append(_build_row(part))


func _build_row(part: Part) -> Dictionary:
	var row := {"kind": "intake", "part": part, "diagnosed": part.nc_diagnosed}
	var box := UiKit.card(_state_color(part))
	row.box = box
	_intake_list.add_child(box)
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
	var familiarity := roundi(GameData.geometry_familiarity_percent(GameData.geometry_name_for_part(part)))
	var source := UiKit.label("For %s - %d%% familiar" % [contract.customer_name if contract != null else "no contract", familiarity], UiKit.FONT_SMALL, "text_dim")
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
	# A casting's metal is remelted, so scrapping it gives revert back.
	if part.is_poured:
		_add_action(actions, "Scrap\n+1 revert", "act_scrap", "danger",
			"Scrap the casting - it's remelted into 1 revert for future trials. You learn nothing from it, and an undiagnosed defect keeps raising risk.",
			func(): GameData.scrap_nc_part(part))
	else:
		_add_action(actions, "Scrap", "act_scrap", "danger",
			"Scrap the part. It hasn't been poured, so there's no metal to recover. You learn nothing from it, and an undiagnosed defect keeps raising risk.",
			func(): GameData.scrap_nc_part(part))
	if part.nc_diagnosed:
		var rework_at := GameData.rework_station_for(part)
		if rework_at != "":
			var station_name: String = GameData.get_station(rework_at).display_name
			var gain := GameData.learning_gain_percent(part, false)
			_add_action(actions, "Rework at %s\n+%s familiarity" % [station_name, _percent(gain)], "act_rework", "warn",
				"Back onto the line to be repaired at %s and learned from: +%s familiarity with %s, one star at each tracked station it passes (whoever runs it learns too). It goes to the shelf's pickup side for a technician to carry. Learning only - it won't ship; once it's cast, its metal is remelted into 1 revert at the end." % [station_name, _percent(gain), GameData.geometry_name_for_part(part)],
				func(): GameData.rework_nc_part(part))
		else:
			var gain := GameData.learning_gain_percent(part, true)
			_add_action(actions, "Scan to learn\n+%s familiarity" % _percent(gain), "act_scan", "go",
				"Can't be repaired. Send it to Structured Light Scan to learn from: +%s familiarity with %s%s. It goes to the shelf's pickup side for a technician to carry, then it's retired%s." % [
					_percent(gain), GameData.geometry_name_for_part(part),
					"" if gain > 0.0 else " (%s is already fully familiar where this defect came from)" % GameData.geometry_name_for_part(part),
					" and remelted into 1 revert" if part.is_poured else ""],
				func(): GameData.scan_nc_part(part))
	box.tooltip_text = "Part #%d - %s\n%s from %s" % [part.part_id, GameData.geometry_name_for_part(part),
		GameData.DEFECT_CATEGORY_LABEL[part.defect_category], origin_name]
	return row


## "+10%" / "+2.5%" - familiarity moves in 2.5% steps (one star at one of
## the four tracked stations).
static func _percent(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "%d%%" % roundi(value)
	return "%.1f%%" % value


func _build_pickup_row(part: Part) -> Dictionary:
	var row := {"kind": "pickup", "part": part}
	var box := UiKit.card("good")
	row.box = box
	_pickup_list.add_child(box)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	box.add_child(line)
	line.add_child(UiKit.framed_icon(UiKit.part_icon(GameData.geometry_name_for_part(part)), 28))

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(info)
	var title := UiKit.label("Part #%d - %s" % [part.part_id, GameData.geometry_name_for_part(part)], UiKit.FONT_BODY, "header_text")
	title.clip_text = true
	info.add_child(title)
	var next_id := GameData.next_station_id_for(part)
	var next_name := _station_name(next_id)
	var plan: String
	if part.scan_to_learn:
		plan = "Scan to learn - to %s" % next_name
	else:
		plan = "Rework at %s - to %s" % [_station_name(GameData.rework_station_for_origin(part)), next_name]
	var plan_label := UiKit.label(plan, UiKit.FONT_SMALL, "text_dim")
	plan_label.clip_text = true
	info.add_child(plan_label)
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

	var actions := VBoxContainer.new()
	actions.custom_minimum_size.x = ACTION_COLUMN_WIDTH
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(actions)
	var send := UiKit.button("Send to\n%s" % next_name, "act_send", "neutral")
	send.pressed.connect(func():
		GameData.send_nc_pickup_part(part)
		_needs_rebuild = true
		_refresh.call_deferred())
	actions.add_child(send)
	row.send = send
	box.tooltip_text = "Part #%d - %s\n%s" % [part.part_id, GameData.geometry_name_for_part(part), plan]
	return row


func _station_name(station_id: String) -> String:
	var station: Station = GameData.station_by_id.get(station_id)
	if station != null:
		return station.station_name
	var def := GameData.get_station(station_id)
	return def.display_name if def != null else station_id


func _update_pickup_row(row: Dictionary) -> void:
	var part: Part = row.part
	var send: Button = row.send
	var destination: Station = GameData.station_by_id.get(GameData.next_station_id_for(part))
	var room := destination != null and destination.can_accept_part()
	send.disabled = not room
	var technicians := 0
	for tech in GameData.technicians:
		if not tech.is_engineer:
			technicians += 1
	var coming := GameData.nc_pickup_incoming
	if coming != null and coming.is_traveling and coming.travel_target_station_id == GameData.NC_PICKUP_ID:
		row.status_icon.texture = UiIcons.get_icon("role_technician")
		row.status_label.text = "%s is coming to pick it up" % coming.technician_name
	elif technicians == 0:
		row.status_icon.texture = UiIcons.get_icon("st_warning")
		row.status_label.text = "No technicians - send it yourself"
	else:
		row.status_icon.texture = UiIcons.get_icon("st_hourglass")
		row.status_label.text = "Waiting for a technician"
	send.tooltip_text = UiText.tip(
		"Carry it to %s's rack yourself. Technicians pick these up on their own." % destination.station_name if room
		else "%s has no room right now - its rack is full." % (destination.station_name if destination != null else "The next station"))


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
	if row.kind == "pickup":
		_update_pickup_row(row)
		return
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
