extends OverlayBase
class_name BoardOverlay

## The Board (design doc 27.7): the live "what is every station doing" list
## plus the Awaiting Transfer list, as two tabs. Replaces the old Dashboard
## and Transfer overlays (Option B's consolidation; the Dashboard's Contracts
## tab is gone - Contracts has its own progress bars now).
##
## Stations tab: one row per station, grouped by room, with ONE action
## button showing the most urgent verb (Fix > Collect > Queue > Upgrade) -
## "one verb per row" (27.6), which is also what fits a ~384px panel. The
## station name is itself a button: it emits station_requested, and main.gd
## pans to that station and opens its Station Detail Menu, where everything
## the single verb doesn't cover (defect fixes, rack, batch size, staffing)
## still lives.
##
## Transfer tab: unchanged from the old Awaiting Transfer overlay - held
## Parts grouped by contract, a Defects-only filter, Part#/Familiarity/
## Defect columns and a "Send to <next station>" button per Part.

signal station_requested(station: Station)

const REFRESH_INTERVAL: float = 0.25
const TAB_STATIONS := 0
const TAB_TRANSFER := 1

const BAR_COLOR_IDLE := Color(0.35, 0.35, 0.38)
const BAR_COLOR_RUNNING := Color(0.92, 0.70, 0.20)
const BAR_COLOR_READY := Color(0.35, 0.80, 0.35)
const BAR_TRACK_COLOR := Color(0.12, 0.11, 0.10)
const HEADER_COLOR := Color(0.85, 0.64, 0.16)
const DEFECT_COLOR := Color(0.88, 0.35, 0.22)

@onready var tabs: TabContainer = %TabContainer
@onready var stations_list: VBoxContainer = %StationsList
@onready var transfer_list: VBoxContainer = %TransferList
@onready var transfer_defects_only_check: CheckBox = %TransferDefectsOnlyCheck

## Set by main.gd right after every Station is spawned.
var station_by_id: Dictionary = {}

var _refresh_elapsed: float = 0.0
var _bar_fill_styles: Dictionary = {} # Color -> StyleBoxFlat


func _on_ready() -> void:
	transfer_defects_only_check.toggled.connect(func(_p): _refresh_transfer_tab.call_deferred())
	GameData.held_parts_changed.connect(_on_held_parts_changed)


func _process(delta: float) -> void:
	if not panel.visible:
		return
	_refresh_elapsed += delta
	if _refresh_elapsed < REFRESH_INTERVAL:
		return
	if _click_in_progress():
		return
	_refresh_elapsed = 0.0
	_refresh()


func _on_open() -> void:
	_refresh_elapsed = 0.0
	_refresh()


## Opens straight to the Transfer tab - the Attention button's target for
## stranded held Parts.
func open_transfer_tab() -> void:
	if not panel.visible:
		toggle()
	tabs.current_tab = TAB_TRANSFER


func _refresh() -> void:
	_refresh_stations_tab()
	_refresh_transfer_tab()


# ---------------------------------------------------------------------------
# Stations tab
# ---------------------------------------------------------------------------

## Persistent rows, updated in place every refresh - rebuilding on the 0.25s
## poll would visibly "pop" (same pattern as every other polled list here).
class StationRow:
	var container: VBoxContainer
	var name_button: Button
	var action_button: Button
	var status_label: Label
	var bar: ProgressBar
	var station: Station = null
	var action: String = ""

var _station_rows: Dictionary = {} # station_id -> StationRow
var _room_headers: Dictionary = {} # room_name -> Label


## GameData.all_real_station_ids() visits stations room by room, so a header
## only needs inserting whenever the room changes.
func _refresh_stations_tab() -> void:
	var last_room := ""
	var next_index := 0
	for id in GameData.all_real_station_ids():
		var station: Station = station_by_id.get(id)
		if station == null:
			continue
		var room_name: String = GameData.get_station(id).room_name
		if room_name != last_room:
			last_room = room_name
			var header: Label = _room_headers.get(room_name)
			if header == null:
				header = Label.new()
				header.add_theme_color_override("font_color", HEADER_COLOR)
				header.text = room_name
				stations_list.add_child(header)
				_room_headers[room_name] = header
			stations_list.move_child(header, next_index)
			next_index += 1

		var row: StationRow = _station_rows.get(id)
		if row == null:
			row = _create_station_row()
			_station_rows[id] = row
			stations_list.add_child(row.container)
		stations_list.move_child(row.container, next_index)
		next_index += 1
		_update_station_row(row, station)


func _create_station_row() -> StationRow:
	var row := StationRow.new()
	row.container = VBoxContainer.new()
	row.container.add_theme_constant_override("separation", 2)

	# Name button (expand-fill) + one no-wrap verb button: CLAUDE.md UI rule
	# 1, and the verb's text is short enough to never need wrapping.
	var line := HBoxContainer.new()
	row.container.add_child(line)
	row.name_button = Button.new()
	row.name_button.flat = true
	row.name_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.name_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.name_button.tooltip_text = "Show this station on the floor"
	row.name_button.pressed.connect(_on_name_pressed.bind(row))
	line.add_child(row.name_button)
	row.action_button = Button.new()
	row.action_button.pressed.connect(_on_action_pressed.bind(row))
	line.add_child(row.action_button)

	# Status text length varies a lot between refreshes - a two-line height
	# floor stops it reflowing every row below (CLAUDE.md UI rule 3).
	row.status_label = Label.new()
	row.status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.status_label.custom_minimum_size = Vector2(0.0, 26.0)
	row.container.add_child(row.status_label)

	row.bar = ProgressBar.new()
	row.bar.show_percentage = false
	row.bar.min_value = 0.0
	row.bar.max_value = 1.0
	row.bar.custom_minimum_size = Vector2(0.0, 8.0)
	row.bar.add_theme_stylebox_override("background", _bar_style(BAR_TRACK_COLOR))
	row.container.add_child(row.bar)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 4.0)
	row.container.add_child(spacer)
	return row


func _update_station_row(row: StationRow, station: Station) -> void:
	row.station = station
	row.name_button.text = station.station_name
	row.status_label.text = station.get_overview_status()

	var is_automatic := station.station_type == Station.StationType.AUTOMATIC
	row.bar.visible = not is_automatic
	if row.bar.visible:
		row.bar.value = _station_progress_fraction(station)
		row.bar.add_theme_stylebox_override("fill", _bar_fill_style(_bar_color_for(station)))

	row.action = _primary_action(station)
	row.action_button.visible = row.action != ""
	match row.action:
		"fix":
			row.action_button.text = "Fix"
			row.action_button.tooltip_text = "A part here has a defect - open the station to fix it"
		"collect":
			row.action_button.text = "Collect"
			row.action_button.tooltip_text = "Move the finished part to Awaiting Transfer"
		"queue":
			row.action_button.text = "Queue"
			row.action_button.tooltip_text = "Start printing a part for an active contract"
		"upgrade":
			var cost := GameData.upgrade_cost_for_tier(station.current_tier + 1)
			row.action_button.text = "Upgrade %dg" % cost
			row.action_button.tooltip_text = "Upgrade to Tier %d" % (station.current_tier + 1)


## The single most urgent verb for this row, or "" for none. Fix and Collect
## follow Station.attention_need()'s own rules; Collect also covers a staffed
## station whose technician is elsewhere (same rule as the Station Detail
## Menu's Collect button). Upgrade only shows when affordable - an
## unaffordable one would be the only button on most rows and say nothing
## useful.
func _primary_action(station: Station) -> String:
	if station.station_type == Station.StationType.AUTOMATIC:
		return ""
	var need := station.attention_need()
	if not need.is_empty() and need.priority == 0:
		return "fix"
	if station.current_state == Station.State.READY and not station.is_technician_present():
		return "collect"
	if station.assigned_technicians.is_empty() and station.is_pipeline_entry \
			and station.current_state == Station.State.IDLE and station.can_start_new_work() \
			and GameData.next_contract_needing_parts() != null:
		return "queue"
	if station.current_tier < 5 and GameData.can_afford_with_gems(GameData.upgrade_cost_for_tier(station.current_tier + 1)):
		return "upgrade"
	return ""


func _on_action_pressed(row: StationRow) -> void:
	if row.station == null:
		return
	match row.action:
		"fix":
			station_requested.emit(row.station)
		"collect":
			row.station.collect_ready_part()
		"queue":
			row.station.queue_new_part()
		"upgrade":
			row.station.try_upgrade()
	_refresh_stations_tab.call_deferred()


func _on_name_pressed(row: StationRow) -> void:
	if row.station != null:
		station_requested.emit(row.station)


## Fraction complete (0.0-1.0). Derived from the station's own timer_bar
## (station.gd keeps it in sync); parallel Shelling reads its soonest run.
func _station_progress_fraction(station: Station) -> float:
	if station.is_parallel_shelling():
		if not station.shelling_ready_parts.is_empty():
			return 1.0
		if station.shelling_active_parts.is_empty():
			return 0.0
		return _fraction_from_bar(station)
	match station.current_state:
		Station.State.READY:
			return 1.0
		Station.State.RUNNING:
			return _fraction_from_bar(station)
	return 0.0


func _fraction_from_bar(station: Station) -> float:
	var bar := station.timer_bar
	if bar == null:
		return 0.0
	return clampf(1.0 - bar.value / maxf(bar.max_value, 0.01), 0.0, 1.0)


func _bar_color_for(station: Station) -> Color:
	if station.is_parallel_shelling():
		if not station.shelling_ready_parts.is_empty():
			return BAR_COLOR_READY
		if not station.shelling_active_parts.is_empty():
			return BAR_COLOR_RUNNING
		return BAR_COLOR_IDLE
	match station.current_state:
		Station.State.READY:
			return BAR_COLOR_READY
		Station.State.RUNNING:
			return BAR_COLOR_RUNNING
	return BAR_COLOR_IDLE


func _bar_fill_style(color: Color) -> StyleBoxFlat:
	if not _bar_fill_styles.has(color):
		_bar_fill_styles[color] = _bar_style(color)
	return _bar_fill_styles[color]


func _bar_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.05, 0.04, 0.03)
	style.set_border_width_all(1)
	style.anti_aliasing = false
	return style


# ---------------------------------------------------------------------------
# Transfer tab (formerly the Awaiting Transfer overlay)
# ---------------------------------------------------------------------------

## A rebuild triggered while the player is mid-click on another row's button
## would eat that click; the 0.25s poll catches up anything skipped here.
func _on_held_parts_changed() -> void:
	if panel.visible and not _click_in_progress():
		_refresh_transfer_tab()


## Grouped by contract, defective Parts first within each group. Held Parts
## churn often enough that this is a full rebuild rather than persistent rows.
func _refresh_transfer_tab() -> void:
	for child in transfer_list.get_children():
		child.queue_free()

	var defects_only := transfer_defects_only_check.button_pressed
	var by_contract: Dictionary = {} # contract_id -> Array[Part]
	for part in GameData.held_parts:
		if defects_only and not part.is_defective:
			continue
		if not by_contract.has(part.contract_id):
			by_contract[part.contract_id] = []
		(by_contract[part.contract_id] as Array).append(part)

	var count := GameData.held_parts.size()
	tabs.set_tab_title(TAB_TRANSFER, "Transfer (%d)" % count if count > 0 else "Transfer")

	if by_contract.is_empty():
		var empty_label := Label.new()
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_label.text = "No defective parts awaiting transfer." if defects_only else "Nothing awaiting transfer."
		transfer_list.add_child(empty_label)
		return

	for contract_id in by_contract.keys():
		var parts: Array = by_contract[contract_id]
		parts.sort_custom(func(a: Part, b: Part) -> bool:
			if a.is_defective != b.is_defective:
				return a.is_defective
			return a.part_id < b.part_id
		)
		var contract := GameData.get_contract(contract_id)
		var header := Label.new()
		header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		header.add_theme_color_override("font_color", HEADER_COLOR)
		header.text = "%s (%d)" % [contract.customer_name if contract != null else "No Contract", parts.size()]
		transfer_list.add_child(header)
		for part in parts:
			_add_transfer_row(part)


func _add_transfer_row(part: Part) -> void:
	var row := HBoxContainer.new()
	transfer_list.add_child(row)

	var id_label := Label.new()
	id_label.custom_minimum_size = Vector2(45.0, 0.0)
	id_label.text = "#%d" % part.part_id
	row.add_child(id_label)

	var familiarity_label := Label.new()
	familiarity_label.custom_minimum_size = Vector2(32.0, 0.0)
	familiarity_label.text = "%d/5" % GameData.average_familiarity_stars(GameData.geometry_name_for_part(part))
	row.add_child(familiarity_label)

	if part.is_defective:
		var defect_label := Label.new()
		defect_label.custom_minimum_size = Vector2(70.0, 0.0)
		defect_label.add_theme_color_override("font_color", DEFECT_COLOR)
		defect_label.text = GameData.DEFECT_CATEGORY_LABEL[part.defect_category]
		row.add_child(defect_label)

	var next_station: Station = station_by_id.get(GameData.next_station_id_for(part))
	var send_button := Button.new()
	if next_station == null:
		send_button.text = "No next station"
		send_button.disabled = true
	else:
		send_button.text = "Send to %s" % next_station.station_name
		send_button.disabled = not next_station.can_accept_part()
		send_button.pressed.connect(_on_send_held_part.bind(part, next_station))
	row.add_child(send_button)


## Same receive_part() path a technician's delivery uses.
func _on_send_held_part(part: Part, target: Station) -> void:
	if not target.can_accept_part():
		_refresh_transfer_tab()
		return
	GameData.release_held_part(part)
	target.receive_part(part)
	_refresh_transfer_tab.call_deferred()
