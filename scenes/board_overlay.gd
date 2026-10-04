extends OverlayBase
class_name BoardOverlay

## The Board (design doc 27.7): the live "what is every station doing" list
## plus the Awaiting Transfer list, as two tabs, in the "Foundry Dispatch"
## style of the user's mockup (assets/inspo/UI/board_UI.png).
##
## Stations tab: a gold strip per room, then one card per station - its
## sprite, name, a short status line (Station.board_status_text()), a
## progress bar, and ONE action button with the most urgent verb (Fix >
## Collect > Start > Queue > Upgrade - "one verb per row", 27.6). Tapping the
## card itself emits station_requested; main.gd pans to that station and
## opens its Station Detail Menu, where everything else lives.
##
## Transfer tab: held Parts grouped by contract, a Defects-only filter, and
## per Part its number, familiarity, defect and a "Send to <next station>"
## button.

signal station_requested(station: Station)

const REFRESH_INTERVAL: float = 0.25
const TAB_STATIONS := 0
const TAB_TRANSFER := 1


@onready var tabs: TabContainer = %TabContainer
@onready var stations_list: VBoxContainer = %StationsList
@onready var transfer_list: VBoxContainer = %TransferList
@onready var transfer_defects_only_check: CheckBox = %TransferDefectsOnlyCheck

## Set by main.gd right after every Station is spawned.
var station_by_id: Dictionary = {}

var _refresh_elapsed: float = 0.0


func _on_ready() -> void:
	transfer_defects_only_check.add_theme_font_size_override("font_size", UiKit.FONT_BODY)
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
	var box: PanelContainer
	var icon: TextureRect
	var name_label: Label
	var status_label: Label
	var bar: ProgressBar
	var action_button: Button
	var station: Station = null
	var action: String = ""
	var press_position: Vector2 = Vector2.ZERO

var _station_rows: Dictionary = {} # station_id -> StationRow
var _room_headers: Dictionary = {} # room_name -> PanelContainer

const ACTION_BUTTON_WIDTH: float = 66.0
const STATUS_BAR_WIDTH: float = 44.0
## Press-to-release movement under this is a tap; more is a scroll drag.
const ROW_TAP_MOVE_THRESHOLD: float = 24.0


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
			var header: PanelContainer = _room_headers.get(room_name)
			if header == null:
				header = UiKit.section(UiKit.room_display_name(room_name), UiKit.room_icon(room_name))
				stations_list.add_child(header)
				_room_headers[room_name] = header
			stations_list.move_child(header, next_index)
			next_index += 1

		var row: StationRow = _station_rows.get(id)
		if row == null:
			row = _create_station_row()
			_station_rows[id] = row
			stations_list.add_child(row.box)
		stations_list.move_child(row.box, next_index)
		next_index += 1
		_update_station_row(row, station)


func _create_station_row() -> StationRow:
	var row := StationRow.new()
	row.box = UiKit.card()
	row.box.tooltip_text = "Tap to show this station on the floor"
	row.box.gui_input.connect(_on_row_gui_input.bind(row))
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 5)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.box.add_child(line)

	row.icon = TextureRect.new()
	row.icon.custom_minimum_size = Vector2(20, 20)
	row.icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	row.icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	row.icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(row.icon)

	# Name over status, both single-line and clipped (no autowrap: UI rule 1).
	var names := VBoxContainer.new()
	names.add_theme_constant_override("separation", 0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(names)
	row.name_label = UiKit.label("")
	row.name_label.clip_text = true
	names.add_child(row.name_label)
	row.status_label = UiKit.label("", UiKit.FONT_SMALL, "text_dim")
	row.status_label.clip_text = true
	names.add_child(row.status_label)

	row.bar = UiKit.bar("gold", 6)
	row.bar.custom_minimum_size.x = STATUS_BAR_WIDTH
	row.bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(row.bar)

	# Fixed width so the bar column lines up whether or not a row has a verb.
	row.action_button = UiKit.button("")
	row.action_button.custom_minimum_size = Vector2(ACTION_BUTTON_WIDTH, 0)
	row.action_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.action_button.clip_text = true
	row.action_button.pressed.connect(_on_action_pressed.bind(row))
	line.add_child(row.action_button)
	return row


func _update_station_row(row: StationRow, station: Station) -> void:
	row.station = station
	row.icon.texture = _station_icon(station)
	row.name_label.text = station.station_name
	var status := station.board_status_text()
	row.status_label.text = status
	var need := station.attention_need()
	var urgent: bool = not need.is_empty() and need.priority == 0
	UiKit.set_label_color(row.status_label, "bad" if urgent else "text_dim")
	UiKit.set_card_border(row.box, "bad" if urgent else "card_border")

	var is_automatic := station.station_type == Station.StationType.AUTOMATIC
	row.bar.modulate.a = 0.0 if is_automatic else 1.0
	row.bar.value = _station_progress_fraction(station)
	UiKit.set_bar_color(row.bar, _bar_color_key(station))

	row.action = _primary_action(station)
	# An empty slot keeps its width (the bar column stays aligned) but is
	# invisible and can't be pressed.
	row.action_button.modulate.a = 0.0 if row.action == "" else 1.0
	row.action_button.disabled = row.action == ""
	match row.action:
		"fix":
			_set_action(row, "Fix", "st_warning", "danger", "A part here has a defect - open the station to deal with it")
		"start":
			_set_action(row, "Start", "act_start", "go", "Start this batch station's cycle with everything loaded")
		"collect":
			_set_action(row, "Collect", "act_collect", "primary", "Move the finished part to Awaiting Transfer")
		"queue":
			_set_action(row, "Queue", "act_queue", "neutral", "Start printing the next queued part")
		"upgrade":
			var cost := GameData.upgrade_cost_for_tier(station.current_tier + 1)
			_set_action(row, "%dg" % cost, "act_upgrade", "neutral", "Upgrade to Tier %d for %dg" % [station.current_tier + 1, cost])
		_:
			_set_action(row, "", "", "neutral", "")


## The station's own sprite, so the row matches the floor - except the
## generated placeholder box (an ImageTexture), which reads as a blank
## square at 20px; those use their room's icon until real art lands.
func _station_icon(station: Station) -> Texture2D:
	var texture: Texture2D = station.station_sprite.texture if station.station_sprite != null else null
	if texture == null or texture is ImageTexture:
		return UiIcons.get_icon(UiKit.room_icon(GameData.get_station(station.station_id).room_name))
	return texture


func _set_action(row: StationRow, text: String, icon_name: String, kind: String, tip: String) -> void:
	row.action_button.text = text
	row.action_button.icon = UiIcons.get_icon(icon_name) if icon_name != "" else null
	row.action_button.tooltip_text = UiText.tip(tip) if tip != "" else ""
	UiKit.set_button_kind(row.action_button, kind)


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
	if station.can_start_batch_cycle_manually():
		return "start"
	if station.assigned_technicians.is_empty() and station.is_pipeline_entry \
			and station.current_state == Station.State.IDLE and station.can_start_new_work() \
			and GameData.has_print_order():
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
		"start":
			row.station.start_batch_cycle_manually()
		"collect":
			row.station.collect_ready_part()
		"queue":
			row.station.queue_new_part()
		"upgrade":
			row.station.try_upgrade()
	_refresh_stations_tab.call_deferred()


## A tap on the card (not a drag - the list must still scroll from a row).
func _on_row_gui_input(event: InputEvent, row: StationRow) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if event.pressed:
		row.press_position = event.global_position
	elif event.global_position.distance_to(row.press_position) < ROW_TAP_MOVE_THRESHOLD and row.station != null:
		station_requested.emit(row.station)


## Fraction complete (0.0-1.0). Derived from the station's own timer_bar
## (station.gd keeps it in sync); parallel and batch stations read their
## soonest run. A loaded-but-waiting batch station shows how full it is.
func _station_progress_fraction(station: Station) -> float:
	if station.uses_parallel_runs():
		if not station.shelling_ready_parts.is_empty():
			return 1.0
		if station.shelling_active_parts.is_empty():
			if station.is_batch_station() and not station.batch_load.is_empty():
				return float(station.batch_load.size()) / maxf(station.batch_cap, 1.0)
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


func _bar_color_key(station: Station) -> String:
	if station.uses_parallel_runs():
		if not station.shelling_ready_parts.is_empty():
			return "good"
		if not station.shelling_active_parts.is_empty() or not station.batch_load.is_empty():
			return "gold"
		return "text_dim"
	match station.current_state:
		Station.State.READY:
			return "good"
		Station.State.RUNNING:
			return "gold"
	return "text_dim"


# ---------------------------------------------------------------------------
# Transfer tab (formerly the Awaiting Transfer overlay)
# ---------------------------------------------------------------------------

## A rebuild triggered while the player is mid-click on another row's button
## would eat that click; the 0.25s poll catches up anything skipped here.
func _on_held_parts_changed() -> void:
	if panel.visible and not _click_in_progress():
		_refresh_transfer_tab()


var _transfer_signature: String = "-"


## Grouped by contract, defective Parts first within each group. Rebuilt only
## when something it shows actually changed (the held set, a defect, a Send
## button's enabled state) - a rebuild on every poll would flicker.
func _refresh_transfer_tab() -> void:
	var defects_only := transfer_defects_only_check.button_pressed
	var by_contract: Dictionary = {} # contract_id -> Array[Part]
	var signature := "%s|" % defects_only
	for part in GameData.held_parts:
		if defects_only and not part.is_defective:
			continue
		if not by_contract.has(part.contract_id):
			by_contract[part.contract_id] = []
		(by_contract[part.contract_id] as Array).append(part)
		var next_station: Station = station_by_id.get(GameData.next_station_id_for(part))
		signature += "%d:%s:%s," % [part.part_id, part.is_defective, next_station != null and next_station.can_accept_part()]

	var count := GameData.held_parts.size()
	tabs.set_tab_title(TAB_TRANSFER, "Transfer (%d)" % count if count > 0 else "Transfer")
	if signature == _transfer_signature:
		return
	_transfer_signature = signature
	MenuLayout.clear(transfer_list)

	if by_contract.is_empty():
		var empty_label := UiKit.label("No defective parts awaiting transfer." if defects_only else "Nothing awaiting transfer.", UiKit.FONT_BODY, "text_dim")
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
		var icon_name := UiKit.part_icon(GameData.geometry_name_for_part(parts[0])) if contract != null else "contracts"
		transfer_list.add_child(UiKit.section("%s (%d)" % [contract.customer_name if contract != null else "No Contract", parts.size()], icon_name))
		for part in parts:
			_add_transfer_row(part)


func _add_transfer_row(part: Part) -> void:
	var box := UiKit.card()
	transfer_list.add_child(box)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	box.add_child(row)

	row.add_child(UiKit.icon(UiKit.part_icon(GameData.geometry_name_for_part(part))))
	var id_label := UiKit.label("#%d" % part.part_id)
	id_label.custom_minimum_size = Vector2(34.0, 0.0)
	id_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(id_label)

	row.add_child(UiKit.icon("reputation"))
	var familiarity_label := UiKit.label("%d/5" % GameData.average_familiarity_stars(GameData.geometry_name_for_part(part)))
	familiarity_label.custom_minimum_size = Vector2(24.0, 0.0)
	familiarity_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(familiarity_label)

	var defect_slot := HBoxContainer.new()
	defect_slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(defect_slot)
	if part.is_defective:
		var pill := UiKit.pill(GameData.DEFECT_CATEGORY_LABEL[part.defect_category], "bad")
		pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		defect_slot.add_child(pill)
	else:
		var ok := UiKit.label("No defects", UiKit.FONT_SMALL, "text_dim")
		ok.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		ok.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		defect_slot.add_child(ok)

	var next_station: Station = station_by_id.get(GameData.next_station_id_for(part))
	var send_button := UiKit.button("", "act_send")
	send_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if next_station == null:
		send_button.text = "No next station"
		send_button.disabled = true
	else:
		send_button.text = "Send to %s" % next_station.station_name
		send_button.disabled = not next_station.can_accept_part()
		if send_button.disabled:
			send_button.tooltip_text = UiText.tip("%s has no room right now" % next_station.station_name)
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
