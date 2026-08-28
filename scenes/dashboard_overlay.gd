extends OverlayBase
class_name Dashboard

## Experimental alternate play surface, built on the gdt-layout-experiment
## branch: a Game Dev Tycoon-style dashboard - big animated progress bars per
## station and per contract, with the core actions (Queue/Collect/Upgrade)
## right on the row, so the game can be played almost entirely from panels
## instead of tapping stations on the floor. Deliberately additive - the
## floor, Station Detail Menu, and every entry-point overlay are all still
## fully functional and unmodified; this is a second lens over the same live
## GameData/Station state, not a replacement. Scoped down from a full GDT
## clone per this session's own request: no fixed single-screen room view, no
## abstracted single-character staff - the multi-room floor and physical
## technician movement are untouched, only the interaction surface is new.
##
## Deliberately NOT covered by this first pass, same as every other overlay's
## early iterations: defect fix buttons (Mortar Patch/Redesign/Scrap), Push
## Through, batch size, the visual queue rack, and Insert-from-Inventory.
## Those stay Station Detail Menu's job for now - this dashboard covers the
## core queue/collect/upgrade loop plus a GDT-style contract-fulfillment
## view, not a full duplicate of every popup's functionality.

const REFRESH_INTERVAL: float = 0.25

const BAR_COLOR_IDLE: Color = Color.WHITE
const BAR_COLOR_RUNNING: Color = Color.YELLOW
const BAR_COLOR_READY: Color = Color.GREEN

@onready var stations_list: VBoxContainer = %StationsList
@onready var contracts_list: VBoxContainer = %ContractsList

## Set by main.gd right after every Station is spawned, same hookup as every
## other overlay that needs one - the only way this overlay can see live
## Station nodes rather than just static StationDefs.
var station_by_id: Dictionary = {}

var _refresh_elapsed: float = 0.0


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


func _refresh() -> void:
	_refresh_stations_tab()
	_refresh_contracts_tab()


# ---------------------------------------------------------------------------
# Stations tab
# ---------------------------------------------------------------------------

## One persistent row per station - built once, updated in place every
## refresh (same jump-prevention pattern as MenuOverlay's Overview tab and
## ShopOverlay's roster: a freshly created Control needs a layout pass to
## reach its final size, so tearing down and recreating rows on every 0.25s
## poll would visibly "pop" even when nothing structurally changed).
class StationRow:
	var container: VBoxContainer
	var header: HBoxContainer
	var name_label: Label
	var status_label: Label
	var bar: ProgressBar
	var actions: HBoxContainer
	var queue_button: Button
	var collect_button: Button
	var upgrade_button: Button
	var station: Station = null

var _station_rows: Dictionary = {} # station_id -> StationRow
var _room_headers: Dictionary = {} # room_name -> Label


## Grouped by room, same reasoning as MenuOverlay's Overview tab - a natural,
## already-existing category for a list of stations. GameData.all_real_station_ids()
## visits stations room-by-room contiguously, so a header only needs
## inserting whenever the room actually changes.
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
				header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				header.add_theme_color_override("font_color", Color(0.55, 0.2, 0.08))
				header.add_theme_font_size_override("font_size", 16)
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

	row.header = HBoxContainer.new()
	row.container.add_child(row.header)

	row.name_label = Label.new()
	row.name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.name_label.custom_minimum_size = Vector2(140.0, 40.0)
	row.header.add_child(row.name_label)

	row.status_label = Label.new()
	row.status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.status_label.custom_minimum_size = Vector2(0.0, 40.0)
	row.status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.header.add_child(row.status_label)

	# The GDT-style touch: a big, always-visible bar (not a tiny inline one)
	# reusing the same idle/running/ready tint Station.gd's own sprite
	# already uses (white/yellow/green), so the color language stays
	# consistent between the floor and this dashboard.
	row.bar = ProgressBar.new()
	row.bar.custom_minimum_size = Vector2(0.0, 22.0)
	row.bar.show_percentage = false
	row.bar.min_value = 0.0
	row.bar.max_value = 1.0
	row.container.add_child(row.bar)

	row.actions = HBoxContainer.new()
	# Fixed minimum height so the row doesn't visibly shrink/grow as buttons
	# individually show/hide across an idle -> running -> ready cycle - same
	# "don't let variable content shift layout" principle as every other
	# overlay's own custom_minimum_size fixes.
	row.actions.custom_minimum_size = Vector2(0.0, 32.0)
	row.container.add_child(row.actions)

	row.queue_button = Button.new()
	row.queue_button.text = "Queue"
	row.queue_button.pressed.connect(_on_queue_pressed.bind(row))
	row.actions.add_child(row.queue_button)

	row.collect_button = Button.new()
	row.collect_button.text = "Collect"
	row.collect_button.pressed.connect(_on_collect_pressed.bind(row))
	row.actions.add_child(row.collect_button)

	row.upgrade_button = Button.new()
	row.upgrade_button.pressed.connect(_on_upgrade_pressed.bind(row))
	row.actions.add_child(row.upgrade_button)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 6.0)
	row.container.add_child(spacer)

	return row


func _update_station_row(row: StationRow, station: Station) -> void:
	row.station = station
	row.name_label.text = station.station_name
	row.status_label.text = station.get_overview_status()

	var is_automatic := station.station_type == Station.StationType.AUTOMATIC
	var staffed := not station.assigned_technicians.is_empty()

	row.bar.visible = not is_automatic
	if row.bar.visible:
		row.bar.value = _station_progress_fraction(station)
		row.bar.modulate = _bar_color_for(station)

	row.queue_button.visible = (
		not is_automatic and not staffed
		and station.is_pipeline_entry and station.current_state == Station.State.IDLE
	)
	if row.queue_button.visible:
		row.queue_button.disabled = not station.can_start_new_work()
		row.queue_button.text = "Queue" if not row.queue_button.disabled else "Blocked"

	# Same "technician might be legitimately elsewhere" rule as
	# StationDetailMenu's own Collect button - see that file's comment.
	row.collect_button.visible = (
		not is_automatic and station.current_state == Station.State.READY
		and (not staffed or not station.is_technician_present())
	)

	row.upgrade_button.visible = not is_automatic and station.current_tier < 5
	if row.upgrade_button.visible:
		var target := station.current_tier + 1
		var cost := GameData.upgrade_cost_for_tier(target)
		row.upgrade_button.text = "Upgrade to Tier %d (%dg)" % [target, cost]
		row.upgrade_button.disabled = not GameData.can_afford_with_gems(cost)


## Fraction complete (0.0-1.0) for whatever a station is currently doing.
## Station itself has no such getter (see this branch's research notes) -
## the single-part path derives it from timer_bar's own value/max_value
## (which station.gd already keeps in sync every _process()), and parallel-
## tier Shelling reads the same soonest-run bar it already drives.
func _station_progress_fraction(station: Station) -> float:
	if station.is_parallel_shelling():
		if not station.shelling_ready_parts.is_empty():
			return 1.0
		if station.shelling_active_parts.is_empty():
			return 0.0
		return _fraction_from_bar(station)
	match station.current_state:
		Station.State.IDLE:
			return 0.0
		Station.State.READY:
			return 1.0
		Station.State.RUNNING:
			return _fraction_from_bar(station)
		_:
			return 0.0


func _fraction_from_bar(station: Station) -> float:
	var bar := station.timer_bar
	if bar == null:
		return 0.0
	return clampf(1.0 - bar.value / max(bar.max_value, 0.01), 0.0, 1.0)


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
		_:
			return BAR_COLOR_IDLE


func _on_queue_pressed(row: StationRow) -> void:
	if row.station != null:
		row.station.queue_new_part()
	_refresh_stations_tab.call_deferred()


func _on_collect_pressed(row: StationRow) -> void:
	if row.station != null:
		row.station.collect_ready_part()
	_refresh_stations_tab.call_deferred()


func _on_upgrade_pressed(row: StationRow) -> void:
	if row.station != null:
		row.station.try_upgrade()
	_refresh_stations_tab.call_deferred()


# ---------------------------------------------------------------------------
# Contracts tab
# ---------------------------------------------------------------------------

## Persistent per-contract row, same "GDT stat bar" treatment as the
## Stations tab above - a big fulfillment bar (quantity shipped / required)
## instead of the Menu Overlay's plain "%d/%d shipped" text column.
class ContractRow:
	var container: VBoxContainer
	var header: HBoxContainer
	var name_label: Label
	var time_label: Label
	var bar: ProgressBar
	var progress_label: Label

var _contract_rows: Dictionary = {} # contract_id -> ContractRow
var _contracts_empty_label: Label = null


func _refresh_contracts_tab() -> void:
	var active := GameData.get_active_contracts()
	var active_ids: Dictionary = {}
	for c in active:
		active_ids[c.contract_id] = true

	for contract_id in _contract_rows.keys().duplicate():
		if not active_ids.has(contract_id):
			var stale: ContractRow = _contract_rows[contract_id]
			stale.container.queue_free()
			_contract_rows.erase(contract_id)

	if active.is_empty():
		if _contracts_empty_label == null:
			_contracts_empty_label = Label.new()
			_contracts_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_contracts_empty_label.text = "No active contracts."
			contracts_list.add_child(_contracts_empty_label)
		return
	if _contracts_empty_label != null:
		_contracts_empty_label.queue_free()
		_contracts_empty_label = null

	for c in active:
		var row: ContractRow = _contract_rows.get(c.contract_id)
		if row == null:
			row = _create_contract_row()
			_contract_rows[c.contract_id] = row
			contracts_list.add_child(row.container)
		row.name_label.text = "%s (%s)" % [c.customer_name, c.tier_label]
		row.time_label.text = "%s left" % _format_time(c.time_remaining)
		var in_pipeline := GameData.count_parts_in_pipeline(c.contract_id)
		row.progress_label.text = "%d/%d shipped (%d in pipe)" % [c.quantity_shipped, c.quantity_required, in_pipeline]
		row.bar.max_value = max(c.quantity_required, 1)
		row.bar.value = c.quantity_shipped


func _create_contract_row() -> ContractRow:
	var row := ContractRow.new()
	row.container = VBoxContainer.new()

	row.header = HBoxContainer.new()
	row.container.add_child(row.header)

	row.name_label = Label.new()
	row.name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.name_label.custom_minimum_size = Vector2(150.0, 0.0)
	row.header.add_child(row.name_label)

	row.time_label = Label.new()
	row.time_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.time_label.custom_minimum_size = Vector2(90.0, 0.0)
	row.header.add_child(row.time_label)

	row.bar = ProgressBar.new()
	row.bar.custom_minimum_size = Vector2(0.0, 22.0)
	row.bar.show_percentage = false
	row.bar.min_value = 0.0
	row.bar.modulate = Color.GREEN
	row.container.add_child(row.bar)

	row.progress_label = Label.new()
	row.progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.container.add_child(row.progress_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 6.0)
	row.container.add_child(spacer)

	return row


func _format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d" % [total / 60, total % 60]
