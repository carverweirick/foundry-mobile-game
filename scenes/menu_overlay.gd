extends CanvasLayer
class_name MenuOverlay

## Emitted when this overlay opens - see ShopOverlay.opened's comment for
## why (main.gd wires all three overlays' opened() signals crosswise so
## only one is ever visible at once).
signal opened()

## Floor menu overlay (design doc Section 6). This is a lens over live
## GameData/Station state, not a separate paused screen - the floor keeps
## running underneath whether the panel is open or closed. Nothing here
## owns state; every tab just polls and re-renders while the panel is open.

const REFRESH_INTERVAL: float = 0.25

@onready var toggle_button: Button = %ToggleButton
@onready var backdrop: Control = %Backdrop
@onready var panel: Panel = %Panel
@onready var tab_container: TabContainer = $Panel/TabContainer
@onready var overview_list: VBoxContainer = %OverviewList
@onready var transfer_list: VBoxContainer = %TransferList
@onready var transfer_defects_only_check: CheckBox = %TransferDefectsOnlyCheck
@onready var contracts_list: VBoxContainer = %ContractsList

## Set by main.gd right after all 11 Station nodes are spawned. This is the
## only way the overlay can see live station state and route held Parts -
## GameData only knows about StationDefs (data), not the scene's live nodes.
var station_by_id: Dictionary = {}

var _refresh_elapsed: float = 0.0


func _ready() -> void:
	tab_container.set_tab_title(1, "Awaiting Transfer")
	toggle_button.pressed.connect(_on_toggle_pressed)
	backdrop.gui_input.connect(_on_backdrop_gui_input)
	transfer_defects_only_check.toggled.connect(func(_p): _refresh_transfer_tab.call_deferred())
	GameData.held_parts_changed.connect(_on_held_parts_changed)
	GameData.contract_updated.connect(func(_c): _on_contract_updated())


func _process(delta: float) -> void:
	if not panel.visible:
		return
	_refresh_elapsed += delta
	if _refresh_elapsed < REFRESH_INTERVAL:
		return
	if _click_in_progress():
		return
	_refresh_elapsed = 0.0
	_refresh_overview_tab()
	_refresh_transfer_tab()
	_refresh_contracts_tab()


## Whether the mouse/touch button is currently held down anywhere - see
## StationDetailMenu._click_in_progress()'s comment for the full rationale.
## Used both by the poll above and the two reactive signal handlers below,
## so a rebuild never lands mid-click regardless of what triggered it.
func _click_in_progress() -> bool:
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


## held_parts_changed/contract_updated used to call straight through to their
## refresh functions - fine most of the time, but a rebuild triggered this
## way while the player is mid-click on some other button in this same list
## (e.g. tapping "Send to X" on one row while a different Part becomes held
## elsewhere) could still eat that click. Skipping here isn't a permanent
## miss either - the regular 0.25s poll above now also refreshes the
## Transfer tab, so anything skipped here catches up within one poll cycle.
func _on_held_parts_changed() -> void:
	if not _click_in_progress():
		_refresh_transfer_tab()


func _on_contract_updated() -> void:
	if not _click_in_progress():
		_refresh_contracts_tab()


func _on_toggle_pressed() -> void:
	_set_open(not panel.visible)


func _on_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_set_open(false)


## Public - called by main.gd when Escape is pressed, so any open overlay
## closes no matter which one it is (design request, this session).
func close() -> void:
	_set_open(false)


func _set_open(open: bool) -> void:
	panel.visible = open
	backdrop.visible = open
	if open:
		_refresh_elapsed = 0.0
		_refresh_overview_tab()
		_refresh_transfer_tab()
		_refresh_contracts_tab()
		opened.emit()


## Bug fix (this session): this used to _clear_list() + rebuild one Label per
## station from scratch on every 0.25s poll, same as the Shop roster did -
## same consequence too, a freshly created Control needs at least one layout
## pass to reach its final size, so tearing down and recreating 11+ Labels
## every 250ms caused a visible "jump" every single poll even though nothing
## structural ever actually changes here (the station list itself is fixed
## once printers are spawned; only each row's status text changes). Now one
## persistent Label per station id, created once and text-updated in place.
var _overview_rows: Dictionary = {} # station_id -> Label
var _overview_room_headers: Dictionary = {} # room_name -> Label

## Design request (this session): organize by a real category instead of one
## flat list - rooms are a natural, already-existing grouping
## (GameData.StationDef.room_name) for a list of stations specifically.
## GameData.all_real_station_ids() already visits stations in PIPELINE_ORDER
## (printers first, then Print Room -> Shell Building -> Furnace Room ->
## Pour Room -> Post Processing), and every station within one room is
## already contiguous in that order, so a room header only needs to be
## inserted whenever the room actually changes, not per-station. Headers and
## rows are both persistent Labels (see _overview_rows' own earlier comment
## for why) reordered in place via move_child() rather than destroyed and
## recreated - reordering doesn't cause the same "pop" a fresh Control would.
func _refresh_overview_tab() -> void:
	var last_room := ""
	var next_index := 0
	for id in GameData.all_real_station_ids():
		var station: Station = station_by_id.get(id)
		if station == null:
			continue
		var room_name: String = GameData.get_station(id).room_name
		if room_name != last_room:
			last_room = room_name
			var header: Label = _overview_room_headers.get(room_name)
			if header == null:
				header = Label.new()
				header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				header.add_theme_color_override("font_color", Color(0.55, 0.2, 0.08))
				header.add_theme_font_size_override("font_size", 16)
				header.text = room_name
				overview_list.add_child(header)
				_overview_room_headers[room_name] = header
			overview_list.move_child(header, next_index)
			next_index += 1

		var row: Label = _overview_rows.get(id)
		if row == null:
			row = Label.new()
			row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			# Fixed 2-line minimum height - same "jumping" fix as the Shop
			# roster's header/carrying labels (see that file's comment for
			# the full rationale). get_overview_status() text length varies a
			# lot (idle/running/ready, rack backlog, current-part info,
			# defect info all appended conditionally), so without this, every
			# other station's row below it in the list shifted whenever one
			# station's status happened to cross a line-wrap threshold.
			row.custom_minimum_size = Vector2(0, 40)
			overview_list.add_child(row)
			_overview_rows[id] = row
		row.text = "  %s: %s" % [station.station_name, station.get_overview_status()]
		overview_list.move_child(row, next_index)
		next_index += 1


## Redesigned this session (design request: "categories they can fall under
## like associated contract... a filter/sort system... a few columns"):
## grouped by contract (a subheader per contract with held Parts, in the
## order those Parts were first held), a "Defects only" filter, real
## Part#/Familiarity/Defect/Action columns instead of one run-on text string
## per row, and defective Parts sorted first within each group so anything
## needing attention isn't buried. Held Parts churn far more than
## stations/technicians do, so unlike the Overview tab and Shop roster this
## still does a full rebuild each refresh rather than persistent widgets -
## its actual *contents* genuinely change shape often enough that there's a
## real, unavoidable "reflow" most of the time anyway, not the "nothing
## changed but it popped" problem those two had.
func _refresh_transfer_tab() -> void:
	_clear_list(transfer_list)

	var defects_only := transfer_defects_only_check.button_pressed
	var by_contract: Dictionary = {} # contract_id -> Array[Part]
	for part in GameData.held_parts:
		if defects_only and not part.is_defective:
			continue
		if not by_contract.has(part.contract_id):
			by_contract[part.contract_id] = []
		(by_contract[part.contract_id] as Array).append(part)

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
		header.add_theme_color_override("font_color", Color(0.55, 0.2, 0.08))
		header.add_theme_font_size_override("font_size", 16)
		header.text = "%s (%d)" % [contract.customer_name if contract != null else "No Contract", parts.size()]
		transfer_list.add_child(header)

		for part in parts:
			_add_transfer_row(part)


func _add_transfer_row(part: Part) -> void:
	var row := HBoxContainer.new()
	transfer_list.add_child(row)

	var contract := GameData.get_contract(part.contract_id)

	var id_label := Label.new()
	id_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	id_label.custom_minimum_size = Vector2(45.0, 0.0)
	id_label.text = "#%d" % part.part_id
	row.add_child(id_label)

	var familiarity_label := Label.new()
	familiarity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	familiarity_label.custom_minimum_size = Vector2(40.0, 0.0)
	# Design doc Section 21.7's quick-glance display: an average star rating
	# everywhere a Part shows up in a list.
	familiarity_label.text = "%d/5" % GameData.average_familiarity_stars(
		contract.geometry_name if contract != null else ""
	)
	row.add_child(familiarity_label)

	if part.is_defective:
		var defect_label := Label.new()
		defect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		defect_label.custom_minimum_size = Vector2(70.0, 0.0)
		defect_label.add_theme_color_override("font_color", Color(0.75, 0.25, 0.1))
		defect_label.text = GameData.DEFECT_CATEGORY_LABEL[part.defect_category]
		row.add_child(defect_label)

	var next_id := GameData.next_station_id_for(part)
	var next_station: Station = station_by_id.get(next_id)
	var send_button := Button.new()
	if next_station == null:
		send_button.text = "No next station"
		send_button.disabled = true
	else:
		send_button.text = "Send to %s" % next_station.station_name
		send_button.disabled = not next_station.can_accept_part()
		send_button.pressed.connect(_on_send_held_part.bind(part, next_station))
	row.add_child(send_button)


## Hands a held Part directly to a Station via the same receive_part() path
## a staffed technician or a manual Send-to-Next tap already uses, then
## drops it out of the holding inventory.
func _on_send_held_part(part: Part, target: Station) -> void:
	if not target.can_accept_part():
		_refresh_transfer_tab() # station filled up since the tab was drawn; re-sync
		return
	GameData.release_held_part(part)
	target.receive_part(part)
	_refresh_overview_tab()


## Persistent per-contract row (same reasoning as the Overview tab above) -
## real Customer/Progress/Time columns instead of one run-on text string.
## Contracts are few and rarely change structurally (only when one
## completes), so this is worth doing the same way.
class ContractRow:
	var container: HBoxContainer
	var customer_label: Label
	var relationship_label: Label
	var progress_label: Label
	var time_label: Label

var _contract_rows: Dictionary = {} # contract_id -> ContractRow
var _contracts_empty_label: Label = null

## Persistent shop-wide summary line, always the first child of
## contracts_list (design doc Section 8's Reputation gating) - same
## persistent-widget-updated-in-place pattern as the Overview tab's rows,
## kept separate from the HUD's own ReputationLabel since this one also
## surfaces the next tier threshold, which the HUD doesn't have room for.
var _reputation_header_label: Label = null

func _refresh_contracts_tab() -> void:
	if _reputation_header_label == null:
		_reputation_header_label = Label.new()
		_reputation_header_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		contracts_list.add_child(_reputation_header_label)
	_reputation_header_label.text = _reputation_summary_text()
	contracts_list.move_child(_reputation_header_label, 0)

	var active := GameData.get_active_contracts()
	var active_ids: Dictionary = {}
	for c in active:
		active_ids[c.contract_id] = true

	for contract_id in _contract_rows.keys().duplicate():
		if not active_ids.has(contract_id):
			var stale_row: ContractRow = _contract_rows[contract_id]
			stale_row.container.queue_free()
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
		var in_pipeline := GameData.count_parts_in_pipeline(c.contract_id)
		var relationship := GameData.relationship_stars_for(c.customer_name)
		row.customer_label.text = "%s (%s)" % [c.customer_name, c.tier_label]
		row.relationship_label.text = "%d/5 rel." % int(round(relationship))
		row.progress_label.text = "%d/%d shipped (%d in pipe)" % [c.quantity_shipped, c.quantity_required, in_pipeline]
		row.time_label.text = "%s left" % _format_time(c.time_remaining)


## Next-tier-threshold text mirrors GameData.REPUTATION_TIER_THRESHOLD
## directly rather than duplicating the numbers here, so this stays correct
## if those constants are ever retuned.
func _reputation_summary_text() -> String:
	var reputation := GameData.reputation
	var next_label := ""
	var next_gap := -1
	for tier in GameData.REPUTATION_TIER_THRESHOLD.keys():
		var threshold: int = GameData.REPUTATION_TIER_THRESHOLD[tier]
		if threshold > reputation and (next_gap < 0 or threshold < next_gap):
			next_gap = threshold
			next_label = Contract.TIER_LABEL[tier]
	if next_label == "":
		return "Shop Reputation: %d/%d (every contract tier unlocked)" % [reputation, GameData.REPUTATION_MAX]
	return "Shop Reputation: %d/%d (%d more unlocks %s)" % [reputation, GameData.REPUTATION_MAX, next_gap - reputation, next_label]


func _create_contract_row() -> ContractRow:
	var row := ContractRow.new()
	row.container = HBoxContainer.new()

	row.customer_label = Label.new()
	row.customer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Same 2-line-fixed-height jump prevention as the Shop roster/Overview
	# rows, applied here too even though these columns already have fixed
	# widths and are less likely to wrap in practice - cheap insurance.
	# Trimmed from 140 (this session, to make room for relationship_label
	# below without pushing the row's total minimum width past the panel's
	# available space - see time_label's own comment further down for the
	# bug that overflow risk was actually causing).
	row.customer_label.custom_minimum_size = Vector2(120.0, 40.0)
	row.container.add_child(row.customer_label)

	row.relationship_label = Label.new()
	row.relationship_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.relationship_label.custom_minimum_size = Vector2(70.0, 40.0)
	row.container.add_child(row.relationship_label)

	row.progress_label = Label.new()
	row.progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.progress_label.custom_minimum_size = Vector2(130.0, 0.0) # trimmed from 150, same reason as customer_label above
	row.container.add_child(row.progress_label)

	row.time_label = Label.new()
	row.time_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Bug fix (this session): this label never had an explicit minimum width,
	# which was harmless back when it was the row's last/only remaining
	# column with the rest of the panel's width free to it - but adding
	# relationship_label above narrowed its share enough that autowrap
	# squeezed it down to a sliver and it wrapped one character per line
	# (the same "vertical line of text" bug already fixed elsewhere in this
	# file - see the Shop roster's "Strategy:" label/Station Detail Menu's
	# "Batch size:" label for the same root cause).
	row.time_label.custom_minimum_size = Vector2(90.0, 0.0)
	row.container.add_child(row.time_label)

	return row


func _format_time(seconds: float) -> String:
	var total := int(seconds)
	return "%d:%02d" % [total / 60, total % 60]


func _clear_list(list: VBoxContainer) -> void:
	for child in list.get_children():
		child.queue_free()
