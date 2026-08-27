extends CanvasLayer
class_name StationDetailMenu

## Emitted when this overlay opens - see OverlayBase.opened's comment for why
## (main.gd wires every overlay's opened() signal generically so only one is
## ever visible at once - see main.gd's _overlays array).
signal opened()

## Per-station popup opened by tapping a station on the floor (main.gd hit-
## tests Station.get_click_rect()). This is the whole surface for driving a
## single Station now that the floor itself is display-only: Queue, Collect,
## batch size, inserting a held Part (the design doc's "next station's own
## Batch Picker" entry point, alongside the Menu Overlay's Awaiting Transfer
## tab), and spending currency to upgrade the tier. Hiring/assigning a
## technician happens in the Shop overlay's Technicians tab instead - this
## popup only shows who's currently staffing the station, read-only.

const REFRESH_INTERVAL: float = 0.25

@onready var backdrop: Control = %Backdrop
@onready var panel: Panel = %Panel
@onready var title_label: Label = %TitleLabel
@onready var close_button: Button = %CloseButton
@onready var status_label: Label = %StatusLabel
@onready var defect_row: HBoxContainer = %DefectRow
@onready var queue_button: Button = %QueueButton
@onready var collect_button: Button = %CollectButton
@onready var push_through_check_box: CheckBox = %PushThroughCheckBox
@onready var batch_row: HBoxContainer = %BatchRow
@onready var batch_spin_box: SpinBox = %BatchSpinBox
@onready var inventory_list: VBoxContainer = %InventoryList
@onready var technician_status_label: Label = %TechnicianStatusLabel
@onready var upgrade_button: Button = %UpgradeButton
@onready var upgrade_rack_button: Button = %UpgradeRackButton
@onready var rack_panel: Panel = %RackPanel
@onready var rack_grid: GridContainer = %RackGrid
@onready var selected_info_label: Label = %SelectedInfoLabel
@onready var selected_fix_row: HBoxContainer = %SelectedFixRow

var _station: Station = null
var _refresh_elapsed: float = 0.0

## Visual queue rack (design doc Section 7's "station queue rack", requested
## as its own always-visible panel rather than the old plain-text Queue
## list it replaces) - 10 fixed slot Buttons (5 top row, 5 bottom, via
## RackGrid's columns=5), built ONCE in _ready() and reused every refresh
## rather than torn down and rebuilt like every other dynamic list in this
## file. That's deliberate, not an oversight: rebuilding from scratch every
## 0.25s poll is exactly what caused the old Shop overlay's hire button to
## intermittently eat its first click (a rebuild landing mid-click destroys
## the very button being pressed) - see StaffOverlay._refresh_live_only()
## (the technician-hiring half of that old Shop panel, now its own overlay).
## A slot the player
## might be actively clicking is exactly the wrong thing to keep recreating.
const RACK_SLOT_COUNT: int = 10
var _rack_slot_buttons: Array[Button] = []
## Index into _station.queue_rack of whichever slot was last tapped, so its
## full detail + fix buttons stay pinned in SelectedInfoLabel/SelectedFixRow
## across refreshes instead of only showing on hover. -1 means nothing selected.
var _selected_rack_index: int = -1

## Design doc Section 21.7's two-tier familiarity display: a quick-glance
## average star everywhere a Part shows up (always in _part_detail_text()),
## and a press-and-hold to break it out per-station. These four fields drive
## that press-and-hold gesture on the rack slot Buttons - see
## _update_long_press()/_on_rack_slot_down()/_on_rack_slot_up().
const LONG_PRESS_SECONDS: float = 0.45
var _pressed_rack_index: int = -1
var _press_elapsed: float = 0.0
var _long_press_fired: bool = false
## Whether the currently pinned SelectedInfoLabel should include the
## per-station familiarity breakdown - only true right after a long-press,
## reset on every new short tap.
var _show_familiarity_detail: bool = false


func _ready() -> void:
	panel.visible = false
	backdrop.visible = false
	rack_panel.visible = false
	close_button.pressed.connect(_on_close_pressed)
	backdrop.gui_input.connect(_on_backdrop_gui_input)
	queue_button.pressed.connect(_on_queue_pressed)
	collect_button.pressed.connect(_on_collect_pressed)
	push_through_check_box.toggled.connect(_on_push_through_toggled)
	batch_spin_box.value_changed.connect(_on_batch_size_changed)
	upgrade_button.pressed.connect(_on_upgrade_pressed)
	upgrade_rack_button.pressed.connect(_on_upgrade_rack_pressed)
	_build_rack_slots()


## Builds the 10 slot Buttons once - see _rack_slot_buttons' comment above
## for why these are never freed/recreated afterward, only their text/
## tooltip/style updated in place by _refresh_rack_grid().
func _build_rack_slots() -> void:
	for i in RACK_SLOT_COUNT:
		var slot := Button.new()
		slot.custom_minimum_size = Vector2(24.0, 24.0)
		slot.add_theme_font_size_override("font_size", 11)
		slot.toggle_mode = false
		# button_down/button_up rather than pressed - a short tap vs. a
		# press-and-hold need to do different things (design doc Section
		# 21.7), so this has to distinguish them itself rather than reacting
		# to Godot's single combined "pressed" event. See _update_long_press().
		slot.button_down.connect(_on_rack_slot_down.bind(i))
		slot.button_up.connect(_on_rack_slot_up.bind(i))
		rack_grid.add_child(slot)
		_rack_slot_buttons.append(slot)


func _process(delta: float) -> void:
	if not panel.visible or _station == null:
		return
	_update_long_press(delta)
	_refresh_elapsed += delta
	if _refresh_elapsed < REFRESH_INTERVAL:
		return
	if _click_in_progress():
		return
	_refresh_elapsed = 0.0
	_refresh()


## Whether the mouse/touch button is currently held down anywhere - a real
## signal the player might be mid-click on a Button this refresh would
## otherwise destroy (queue_button/collect_button/upgrade buttons/Insert/fix
## buttons in inventory_list, none of which are the persistent rack-slot
## Buttons, so they all get torn down and rebuilt fresh every _refresh()).
## Godot doesn't atomically finish a Button's own press-to-release handling
## before other code can run, so a rebuild landing in between - a real,
## human-timescale race, well within normal click duration - can silently eat
## the click. This generalizes what was previously several individually
## patched trouble spots (the old Shop overlay's Hire button, its
## routing-strategy dropdown) into one check used everywhere a list gets
## rebuilt on a timer or a reactive signal, in this file and every OverlayBase
## subclass (see that class's own _click_in_progress()) - skipping a refresh
## here just means it retries next frame/poll instead, once the click has
## actually finished.
func _click_in_progress() -> bool:
	return Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)


func _on_rack_slot_down(index: int) -> void:
	_pressed_rack_index = index
	_press_elapsed = 0.0
	_long_press_fired = false


func _on_rack_slot_up(index: int) -> void:
	if _pressed_rack_index != index:
		return
	if not _long_press_fired:
		_on_rack_slot_pressed(index)
	_pressed_rack_index = -1


## Design doc Section 21.7: "press-and-hold on the part opens a detailed view
## breaking familiarity out by station." A short tap (the normal case,
## handled in _on_rack_slot_up() above once released without ever crossing
## LONG_PRESS_SECONDS) just selects/pins the slot's normal detail, same as
## before this session; holding past the threshold fires once, additionally
## showing the per-station familiarity breakdown in that same pinned detail.
func _update_long_press(delta: float) -> void:
	if _pressed_rack_index < 0 or _long_press_fired:
		return
	_press_elapsed += delta
	if _press_elapsed < LONG_PRESS_SECONDS:
		return
	_long_press_fired = true
	_on_rack_slot_pressed(_pressed_rack_index, true)


## Called by main.gd when a station on the floor is tapped.
func open_for(station: Station) -> void:
	_station = station
	panel.visible = true
	backdrop.visible = true
	rack_panel.visible = true
	_selected_rack_index = -1
	_show_familiarity_detail = false
	_pressed_rack_index = -1
	_long_press_fired = false
	_refresh_elapsed = 0.0
	_refresh()
	opened.emit()


## Public - called by main.gd when Escape is pressed, so any open overlay
## closes no matter which one it is (design request, this session).
func close() -> void:
	_on_close_pressed()


func _on_close_pressed() -> void:
	panel.visible = false
	backdrop.visible = false
	rack_panel.visible = false
	_station = null


func _on_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_close_pressed()


func _on_queue_pressed() -> void:
	if _station != null:
		_station.queue_new_part()
	_refresh.call_deferred()


func _on_collect_pressed() -> void:
	if _station != null:
		_station.collect_ready_part()
	_refresh.call_deferred()


func _on_push_through_toggled(pressed: bool) -> void:
	if _station != null:
		_station.set_push_through_armed(pressed)


func _on_batch_size_changed(value: float) -> void:
	if _station != null:
		_station.set_batch_size(int(value))


func _on_upgrade_pressed() -> void:
	if _station != null:
		_station.try_upgrade()
	_refresh.call_deferred()


func _on_upgrade_rack_pressed() -> void:
	if _station != null:
		_station.try_upgrade_rack()
	_refresh.call_deferred()


## Deferred, not direct: this rebuilds inventory_list, which destroys the
## very Insert button this handler is still running because of (queue_free()
## on a Control mid-click confuses Godot's input handling for whatever
## replaces it) - see the same fix in StaffOverlay for the checkbox grid.
func _on_insert_part(part: Part) -> void:
	if _station == null or not _station.can_accept_part():
		_refresh.call_deferred() # station filled up since the list was drawn; re-sync
		return
	GameData.release_held_part(part)
	_station.receive_part(part)
	_refresh.call_deferred()


func _refresh() -> void:
	if _station == null:
		return

	title_label.text = "%s (Tier %d)" % [_station.station_name, _station.current_tier]
	status_label.text = _station.get_overview_status()

	var staffed := not _station.assigned_technicians.is_empty()
	var is_automatic := _station.station_type == Station.StationType.AUTOMATIC

	queue_button.visible = (
		not is_automatic and not staffed
		and _station.is_pipeline_entry and _station.current_state == Station.State.IDLE
	)
	if queue_button.visible:
		# Bug fix (this session): Station.can_start_new_work() now blocks
		# queuing a new Part when the very next station has no room, or when
		# too many defective Parts are already sitting unaddressed - see its
		# own comment. Disabled-with-explanation here rather than just
		# hidden, so it's clear why nothing happens on tap instead of looking
		# broken.
		queue_button.disabled = not _station.can_start_new_work()
		queue_button.text = "Queue Print Job" if not queue_button.disabled else "Blocked - clear the backlog first"

	# Bug fix (this session): available whenever this station's OWN assigned
	# technician isn't the one currently physically here to route it
	# themselves - not just when fully unstaffed. A technician assigned to
	# several stations can be away working another one for a long stretch
	# (see Technician.pick_next_station()); previously Collect was hidden the
	# instant ANY technician was assigned here, leaving no way for the player
	# to free up a Ready Part stuck at a staffed-but-currently-neglected
	# station - reported as "there's no way for parts to make it to ship."
	collect_button.visible = (
		not is_automatic and _station.current_state == Station.State.READY
		and (not staffed or not _station.is_technician_present())
	)
	if collect_button.visible:
		collect_button.text = "Collect" if not staffed else "Collect (technician is elsewhere)"

	# Design doc Section 21.6: Push Through is generalized beyond Pour to
	# Shelling/Burnout/Mold Prep too - see GameData.PUSH_THROUGH_ELIGIBLE_STATIONS.
	push_through_check_box.visible = GameData.PUSH_THROUGH_ELIGIBLE_STATIONS.has(_station.station_id)
	if push_through_check_box.visible:
		push_through_check_box.button_pressed = _station.push_through_armed

	_refresh_defect_row()

	batch_row.visible = (
		not is_automatic and _station.station_type == Station.StationType.BATCHED and not staffed
	)
	if batch_row.visible:
		batch_spin_box.min_value = 1
		batch_spin_box.max_value = max(_station.batch_cap, 1)
		batch_spin_box.value = _station.batch_size
		batch_spin_box.editable = _station.current_state == Station.State.IDLE

	_refresh_rack_grid()
	_refresh_inventory_list()

	if staffed:
		# Design request, this session: several technicians can now be
		# assigned to the same station at once, so this lists every one of
		# them rather than assuming just one - and calls out which single one
		# (if any) is actually the active_worker running the station right
		# now versus just visiting to drop off cargo, since that distinction
		# is new and worth surfacing.
		var lines: Array[String] = []
		for tech in _station.assigned_technicians:
			var extra := ""
			if tech.has_multiple_real_stations():
				extra = ", %d%% productivity here (working %d stations)" % [
					roundi(tech.productivity_multiplier * 100.0), tech.real_assigned_station_ids().size()
				]
			var where: String
			if tech.current_station_id == _station.station_id:
				var role := "working" if _station.active_worker == tech else "visiting"
				where = "here (%s), interacting" % role if tech.is_interacting else "here (%s)" % role
			elif tech.is_traveling:
				where = "walking to %s" % _display_name_for(tech.travel_target_station_id)
			else:
				where = "currently at %s" % _display_name_for(tech.current_station_id)
			var carrying := ""
			if not tech.carried_parts.is_empty():
				carrying = " - carrying %s" % _carried_parts_summary(tech)
			lines.append("%s (%s)%s - %s%s" % [
				tech.technician_name, tech.tier_label, extra, where, carrying
			])
		technician_status_label.text = "Staffed:\n" + "\n".join(PackedStringArray(lines))
	else:
		technician_status_label.text = "Unstaffed - hire and assign from the Shop"

	upgrade_button.visible = not is_automatic and _station.current_tier < 5
	if upgrade_button.visible:
		var target := _station.current_tier + 1
		var cost := GameData.upgrade_cost_for_tier(target)
		upgrade_button.text = "Upgrade to Tier %d (%dg)" % [target, cost]
		upgrade_button.disabled = not GameData.can_afford(cost)

	upgrade_rack_button.visible = not is_automatic and _station.rack_capacity < Station.MAX_RACK_CAPACITY
	if upgrade_rack_button.visible:
		var rack_target := _station.rack_capacity + 1
		var rack_cost := GameData.rack_upgrade_cost_for(rack_target)
		upgrade_rack_button.text = "Upgrade Rack to %d slots (%dg)" % [rack_target, rack_cost]
		upgrade_rack_button.disabled = not GameData.can_afford(rack_cost)


## Design doc Section 9's two per-Part fix paths (Mortar Patch, Shell Crack
## only, and Redesign, any category) - the third, a specialist, is a
## standing hire rather than a per-Part action, see StaffOverlay's
## Specialists tab. Shown right under the main status line for whichever
## Part is actively running here.
func _refresh_defect_row() -> void:
	_clear_list(defect_row)

	# Parallel shelling (design doc Section 21.4) can have several Parts
	## simultaneously active/ready, unlike every other station's single
	## current_part - list fix buttons for every flagged one, not just one.
	if _station.is_parallel_shelling():
		var any := false
		for run in _station.shelling_active_parts:
			if run.part.is_defective:
				_add_defect_fix_buttons(defect_row, run.part)
				any = true
		for part in _station.shelling_ready_parts:
			if part.is_defective:
				_add_defect_fix_buttons(defect_row, part)
				any = true
		defect_row.visible = any
		return

	var part := _station.current_part
	if part == null or not part.is_defective:
		defect_row.visible = false
		return
	defect_row.visible = true
	_add_defect_fix_buttons(defect_row, part)


## Shared by the current-part DefectRow above and each defective row in the
## Queue (rack) and Insert-from-Inventory lists below - anywhere a defective
## Part is shown gets the same two fix buttons.
func _add_defect_fix_buttons(row: Container, part: Part) -> void:
	if not part.is_defective:
		return
	# Design doc Section 21.4: Mortar Patch "happens at this station" (Mold
	# Prep) now, revised from a free-floating action available anywhere a
	# defective part was shown. Scoped here rather than in
	# GameData.can_mortar_patch() (which stays the pure category check, Shell
	# Crack only) since this is specifically about where the UI offers it,
	# not whether the part is eligible at all.
	if GameData.can_mortar_patch(part) and _station.station_id == "mold_prep":
		var mortar := Button.new()
		mortar.text = "Mortar Patch (%dg)" % GameData.MORTAR_PATCH_COST
		mortar.disabled = not GameData.can_afford(GameData.MORTAR_PATCH_COST)
		mortar.pressed.connect(_on_fix_defect.bind(part, false))
		row.add_child(mortar)

	var redesign := Button.new()
	redesign.text = "Redesign (%dg)" % GameData.REDESIGN_COST
	redesign.disabled = not GameData.can_afford(GameData.REDESIGN_COST)
	redesign.pressed.connect(_on_fix_defect.bind(part, true))
	row.add_child(redesign)

	# Design doc Section 21.6: "the one case where not proceeding makes
	# sense" - only ever appears once the player has very high familiarity
	# with this geometry (GameData.can_scrap_for_expertise()), never on a
	# novel or lightly-familiar one. The button text itself surfaces the
	# weakest-link familiarity as a percentage right in this exact
	# proceed-with-defect moment, per Section 21.7: "the prompt also surfaces
	# the single weakest-link station's familiarity as a percentage... since
	# that is the number that actually matters for judging the specific risk."
	if GameData.can_scrap_for_expertise(part):
		var weakest_percent := GameData.weakest_familiarity_percent(GameData.geometry_name_for_part(part))
		var scrap := Button.new()
		scrap.text = "Scrap - won't meet tolerance (weakest link %d%% familiar)" % weakest_percent
		scrap.pressed.connect(_on_scrap_part.bind(part))
		row.add_child(scrap)


func _on_fix_defect(part: Part, is_redesign: bool) -> void:
	if is_redesign:
		GameData.redesign_defect(part)
	else:
		GameData.mortar_patch_defect(part)
	_refresh.call_deferred()


func _on_scrap_part(part: Part) -> void:
	if GameData.scrap_part_for_expertise(part):
		if _station != null:
			_station.remove_part(part)
		GameData.release_held_part(part)
	_refresh.call_deferred()


## Prefers the live Station's own station_name (e.g. "Printing #2" for a
## specific printer instance) over the shared StationDef.display_name, which
## can't tell printer instances apart from each other (design doc Section 21.2).
func _display_name_for(station_id: String) -> String:
	var station: Station = GameData.station_by_id.get(station_id)
	if station != null:
		return station.station_name
	var def := GameData.get_station(station_id)
	return def.display_name if def != null else station_id


## "Part #3 (Acme Co.) -> Deplate, Part #7 (Acme Co.) -> UV Cure" - what a
## technician is physically holding right now and where each piece is bound,
## not just a bare count, so it's clear this isn't unlimited inventory.
func _carried_parts_summary(tech: Technician) -> String:
	var pieces: Array[String] = []
	for part in tech.carried_parts:
		var contract := GameData.get_contract(part.contract_id)
		var dest := _display_name_for(GameData.next_station_id_for(part))
		pieces.append("#%d (%s) -> %s" % [
			part.part_id, contract.customer_name if contract != null else "no contract", dest
		])
	return "%s [%d/%d]" % [", ".join(PackedStringArray(pieces)), tech.carried_parts.size(), Technician.CARRY_CAPACITY]


## Visual view of this station's own queue_rack - the Parts already here
## waiting their turn behind current_part, distinct from the Insert list
## below (which is GameData.held_parts, Parts elsewhere waiting to be routed
## in). Updates the 10 persistent slot Buttons in place (see
## _rack_slot_buttons) rather than rebuilding them - slot i shows
## queue_rack[i] if present, otherwise renders as an empty/dim slot.
func _refresh_rack_grid() -> void:
	if _station == null:
		return

	var rack := _station.queue_rack
	for i in RACK_SLOT_COUNT:
		var slot := _rack_slot_buttons[i]
		if i < rack.size():
			var part := rack[i]
			slot.disabled = false
			slot.text = "%d!" % part.part_id if part.is_defective else "%d" % part.part_id
			slot.tooltip_text = _part_detail_text(part)
			slot.modulate = Color(1.0, 0.55, 0.4) if part.is_defective else Color.WHITE
		else:
			slot.disabled = true
			slot.text = ""
			slot.tooltip_text = ""
			slot.modulate = Color(1.0, 1.0, 1.0, 0.35)

	if _selected_rack_index >= rack.size():
		_selected_rack_index = -1
		_show_familiarity_detail = false
	_refresh_selected_info()


func _on_rack_slot_pressed(index: int, show_familiarity_detail: bool = false) -> void:
	_selected_rack_index = index
	_show_familiarity_detail = show_familiarity_detail
	_refresh_selected_info()


## The selected slot's full detail (same text as its hover tooltip, but
## pinned so it doesn't disappear when the mouse moves away), the per-station
## familiarity breakdown if this selection came from a press-and-hold (design
## doc Section 21.7 - see _update_long_press()), plus, if that Part is
## flagged, the same Mortar Patch/Redesign/Scrap buttons every other
## defective-Part view in this popup uses.
func _refresh_selected_info() -> void:
	_clear_list(selected_fix_row)
	if _station == null or _selected_rack_index < 0 or _selected_rack_index >= _station.queue_rack.size():
		selected_info_label.text = "Tap a slot to see part details, or press and hold for familiarity detail."
		return
	var part := _station.queue_rack[_selected_rack_index]
	var text := _part_detail_text(part)
	if _show_familiarity_detail:
		text += "\n" + _part_familiarity_breakdown_text(part)
	selected_info_label.text = text
	_add_defect_fix_buttons(selected_fix_row, part)


## Design doc Section 21.7's "detail view": per-station familiarity, not just
## the quick-glance average already in _part_detail_text() below.
func _part_familiarity_breakdown_text(part: Part) -> String:
	var geometry_name := GameData.geometry_name_for_part(part)
	if geometry_name == "":
		return "Familiarity by station: no contract"
	var lines: Array[String] = ["Familiarity by station:"]
	for station_id in GameData.FAMILIARITY_TRACKED_STATIONS:
		var stars := GameData.familiarity_stars_for(geometry_name, station_id)
		lines.append("  %s: %d/5" % [_display_name_for(station_id), stars])
	return "\n".join(PackedStringArray(lines))


## Shared by a rack slot's hover tooltip and the pinned SelectedInfoLabel -
## everything worth knowing about a Part sitting in the rack: which contract
## it's for, its quick-glance average familiarity (design doc Section 21.7 -
## the four per-station values averaged into one star rating), where it
## physically is right now, where it's headed next, and its defect status if any.
func _part_detail_text(part: Part) -> String:
	var contract := GameData.get_contract(part.contract_id)
	var lines: Array[String] = []
	lines.append("Part #%d" % part.part_id)
	if contract != null:
		var geometry_name := GameData.geometry_name_for_part(part)
		lines.append("Contract: %s (%s, %s)" % [contract.customer_name, geometry_name, GameData.alloy_name_for_part(part)])
		lines.append("Familiarity: %d/5 stars (avg)" % GameData.average_familiarity_stars(geometry_name))
	else:
		lines.append("Contract: none")
	lines.append("Stage: waiting in queue at %s" % _station.station_name)
	var next_id := GameData.next_station_id_for(part)
	if next_id == "":
		lines.append("Next: none (end of line)")
	else:
		lines.append("Next: %s" % _display_name_for(next_id))
	if part.is_defective:
		var label: String = GameData.DEFECT_CATEGORY_LABEL[part.defect_category]
		if part.defect_escalated:
			lines.append("Defect: %s (ESCALATED)" % label)
		else:
			lines.append("Defect: %s (%.0fs to address)" % [label, part.defect_time_remaining])
	else:
		lines.append("Defect: none known")
	return "\n".join(PackedStringArray(lines))


## Redesigned this session (design request: "a few columns... instead of
## just like a text file") - real Part#/Contract/Familiarity/Defect columns
## instead of one run-on text string per row, and defective parts surfaced
## first (then by part number) instead of plain arrival order, so anything
## needing attention isn't buried if several parts are compatible here.
func _refresh_inventory_list() -> void:
	_clear_list(inventory_list)
	if _station == null:
		return

	var compatible: Array[Part] = []
	for part in GameData.held_parts:
		if GameData.next_station_id_for(part) == _station.station_id:
			compatible.append(part)

	if compatible.is_empty():
		var empty_label := Label.new()
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_label.text = "No compatible parts held."
		inventory_list.add_child(empty_label)
		return

	compatible.sort_custom(func(a: Part, b: Part) -> bool:
		if a.is_defective != b.is_defective:
			return a.is_defective
		return a.part_id < b.part_id
	)

	for part in compatible:
		var row := HBoxContainer.new()
		var contract := GameData.get_contract(part.contract_id)

		var id_label := Label.new()
		id_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		id_label.custom_minimum_size = Vector2(35.0, 0.0)
		id_label.text = "#%d" % part.part_id
		row.add_child(id_label)

		var contract_label := Label.new()
		contract_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		contract_label.custom_minimum_size = Vector2(95.0, 0.0)
		contract_label.text = contract.customer_name if contract != null else "no contract"
		row.add_child(contract_label)

		var familiarity_label := Label.new()
		familiarity_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		familiarity_label.custom_minimum_size = Vector2(40.0, 0.0)
		# Design doc Section 21.7's quick-glance display: an average star
		# rating everywhere a Part shows up in a list, not just the rack panel.
		familiarity_label.text = "%d/5" % GameData.average_familiarity_stars(
			GameData.geometry_name_for_part(part)
		)
		row.add_child(familiarity_label)

		if part.is_defective:
			var defect_label := Label.new()
			defect_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			defect_label.custom_minimum_size = Vector2(70.0, 0.0)
			defect_label.add_theme_color_override("font_color", Color(0.75, 0.25, 0.1))
			defect_label.text = _defect_marker(part).trim_prefix(" - DEFECT: ")
			row.add_child(defect_label)

		var insert_button := Button.new()
		insert_button.text = "Insert"
		insert_button.disabled = not _station.can_accept_part()
		insert_button.pressed.connect(_on_insert_part.bind(part))
		row.add_child(insert_button)
		_add_defect_fix_buttons(row, part)

		inventory_list.add_child(row)


func _clear_list(list: Container) -> void:
	for child in list.get_children():
		child.queue_free()


## " - DEFECT: <category>" (plus "(ESCALATED)" if its grace period already
## lapsed) for a flagged Part in a Queue/Insert list row, otherwise empty
## (design doc Section 9). No countdown here unlike Station._defect_suffix()
## - that level of detail belongs to the one active part the main status
## line already covers; a list of several racked/held Parts just needs the
## category (and whether it's now escalated) at a glance.
func _defect_marker(part: Part) -> String:
	if not part.is_defective:
		return ""
	var label: String = GameData.DEFECT_CATEGORY_LABEL[part.defect_category]
	if part.defect_escalated:
		return " - DEFECT: %s (ESCALATED)" % label
	return " - DEFECT: %s" % label
