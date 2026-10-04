extends CanvasLayer
class_name StationDetailMenu

## Emitted when this overlay opens - main.gd wires every overlay's opened()
## so only one is ever visible at once.
signal opened()

## Per-station popup, opened by tapping a station on the floor (main.gd hit-
## tests Station.get_click_rect()) or from the Board. The whole surface for
## driving one Station, as a single half-width panel so the floor stays
## visible beside it (the user's mockup, assets/inspo/UI/station_UI1.png):
##
##   header      - the station's sprite, name + tier, status, progress + time
##   defect      - fix buttons for a flagged part at the station (rare now
##                 that defects go to the NC shelf, but parallel/batch
##                 stations can still hold one mid-run)
##   rack        - the Queue Rack as a 5x2 grid of part slots beside the
##                 action buttons (Queue / Collect / Start cycle / upgrades);
##                 tapping a slot pins that part's detail below, holding it
##                 adds the per-station familiarity breakdown
##   options     - Push Through and batch size, where they apply
##   inventory   - Awaiting Transfer parts bound here, with Insert
##   technicians - who's here, walking, or elsewhere (every technician
##                 covers every station, so there's nothing to assign)
##
## Refresh discipline (CLAUDE.md UI rules): every widget is built once and
## updated in place on the 0.25s poll; the two lists that can change size
## (inventory, technicians) rebuild only when what they show changes.
## Nothing refreshes mid-click, and every button handler defers its refresh.

const REFRESH_INTERVAL: float = 0.25
const RACK_SLOT_COUNT: int = 10
const RACK_SLOT_SIZE: float = 24.0
## Design doc Section 21.7: a short tap pins a rack part's detail; holding
## past this also breaks familiarity out by station.
const LONG_PRESS_SECONDS: float = 0.45

@onready var backdrop: Control = %Backdrop
@onready var panel: Panel = %Panel
@onready var content: VBoxContainer = %Content

var _station: Station = null
var _refresh_elapsed: float = 0.0

# Header.
var _sprite: TextureRect
var _title: Label
var _status: Label
var _progress: ProgressBar
var _time: Label

# Defect strip.
var _defect_card: PanelContainer
var _defect_label: Label
var _defect_actions: HFlowContainer
var _defect_signature: String = ""

# Rack + actions.
var _rack_title: Label
var _rack_slots: Array[Button] = []
var _queue_button: Button
var _collect_button: Button
var _start_cycle_button: Button
var _upgrade_button: Button
var _upgrade_rack_button: Button
var _selected_rack_index: int = -1
var _show_familiarity_detail: bool = false
var _pressed_rack_index: int = -1
var _press_elapsed: float = 0.0
var _long_press_fired: bool = false
var _selected_card: PanelContainer
var _selected_icon: PanelContainer
var _selected_label: Label
var _selected_actions: HFlowContainer
var _selected_signature: String = ""

# Options.
var _push_through_check: CheckBox
var _batch_row: HBoxContainer
var _batch_spin: SpinBox

# Lists.
var _inventory_header: PanelContainer
var _inventory_list: VBoxContainer
var _inventory_signature: String = "-"
var _tech_header: PanelContainer
var _tech_list: VBoxContainer
var _tech_rows: Dictionary = {} # Technician -> {box, where, state}


func _ready() -> void:
	panel.visible = false
	backdrop.visible = false
	backdrop.gui_input.connect(_on_backdrop_gui_input)
	content.add_theme_constant_override("separation", 5)
	_build_header()
	_build_defect_strip()
	_build_rack()
	_build_options()
	_build_lists()
	# Drags that start on a button inside the popup's scroll must still scroll
	# it, and wrapping text must not make it jump while the player taps.
	TouchScroll.watch(panel)
	MenuLayout.watch(panel)
	# panel is a direct CanvasLayer child, so it needs .theme set directly
	# (see ThemeManager's header comment).
	ThemeManager.theme_changed.connect(func(_choice): ThemeManager.apply_theme_to(panel))
	ThemeManager.apply_theme_to(panel)


# ---------------------------------------------------------------------------
# Building (once)
# ---------------------------------------------------------------------------

func _build_header() -> void:
	var card := UiKit.card()
	content.add_child(card)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	card.add_child(line)
	var frame := UiKit.framed_icon("factory", 36)
	_sprite = frame.get_child(0)
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	line.add_child(frame)

	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(info)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 4)
	info.add_child(top)
	_title = UiKit.label("", UiKit.FONT_TITLE, "header_text")
	_title.clip_text = true
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_title)
	var close_button := UiKit.button("", "st_cross")
	close_button.tooltip_text = "Close"
	close_button.pressed.connect(close)
	top.add_child(close_button)
	# Status length varies a lot between refreshes - a two-line floor stops
	# everything below it jumping (UI rule 3).
	_status = UiKit.label("", UiKit.FONT_SMALL)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size.y = 20.0
	info.add_child(_status)
	var bar_line := HBoxContainer.new()
	bar_line.add_theme_constant_override("separation", 4)
	info.add_child(bar_line)
	_progress = UiKit.bar("gold", 6)
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar_line.add_child(_progress)
	_time = UiKit.label("", UiKit.FONT_SMALL)
	_time.custom_minimum_size.x = 38.0
	_time.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bar_line.add_child(_time)


func _build_defect_strip() -> void:
	_defect_card = UiKit.card("bad")
	content.add_child(_defect_card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	_defect_card.add_child(body)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	body.add_child(head)
	head.add_child(UiKit.icon("st_warning"))
	_defect_label = UiKit.label("", UiKit.FONT_BODY, "bad")
	_defect_label.clip_text = true
	_defect_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_defect_label)
	# Button count/width varies per part - HFlowContainer (UI rule 2).
	_defect_actions = HFlowContainer.new()
	_defect_actions.add_theme_constant_override("h_separation", 3)
	_defect_actions.add_theme_constant_override("v_separation", 3)
	body.add_child(_defect_actions)


func _build_rack() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	content.add_child(row)

	var rack := VBoxContainer.new()
	rack.add_theme_constant_override("separation", 3)
	row.add_child(rack)
	_rack_title = UiKit.label("", UiKit.FONT_SMALL, "header_text")
	rack.add_child(_rack_title)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	rack.add_child(grid)
	# Built once and updated in place - a slot the player may be pressing
	# must never be freed under them.
	for i in RACK_SLOT_COUNT:
		var slot := UiKit.button("")
		slot.custom_minimum_size = Vector2(RACK_SLOT_SIZE, RACK_SLOT_SIZE)
		slot.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		slot.expand_icon = false
		# button_down/up, not pressed: a tap and a press-and-hold do
		# different things (see _update_long_press()).
		slot.button_down.connect(_on_rack_slot_down.bind(i))
		slot.button_up.connect(_on_rack_slot_up.bind(i))
		grid.add_child(slot)
		_rack_slots.append(slot)

	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 3)
	actions.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(actions)
	_queue_button = _action_button(actions, "act_queue", "primary", _on_queue_pressed)
	_collect_button = _action_button(actions, "act_collect", "primary", _on_collect_pressed)
	_start_cycle_button = _action_button(actions, "act_start", "go", _on_start_cycle_pressed)
	_upgrade_button = _action_button(actions, "act_upgrade", "neutral", _on_upgrade_pressed)
	_upgrade_rack_button = _action_button(actions, "act_rack", "neutral", _on_upgrade_rack_pressed)

	# The tapped rack part's detail, pinned.
	_selected_card = UiKit.card("gold")
	content.add_child(_selected_card)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	_selected_card.add_child(line)
	_selected_icon = UiKit.framed_icon("part_bracket", 24)
	_selected_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	line.add_child(_selected_icon)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 3)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(info)
	_selected_label = UiKit.label("", UiKit.FONT_SMALL)
	_selected_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(_selected_label)
	_selected_actions = HFlowContainer.new()
	_selected_actions.add_theme_constant_override("h_separation", 3)
	_selected_actions.add_theme_constant_override("v_separation", 3)
	info.add_child(_selected_actions)


func _action_button(parent: Container, icon_name: String, kind: String, handler: Callable) -> Button:
	var b := UiKit.button("", icon_name, kind)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.pressed.connect(handler)
	parent.add_child(b)
	return b


func _build_options() -> void:
	_push_through_check = CheckBox.new()
	_push_through_check.text = "Push Through next part (risky)"
	_push_through_check.add_theme_font_size_override("font_size", UiKit.FONT_BODY)
	_push_through_check.focus_mode = Control.FOCUS_NONE
	_push_through_check.tooltip_text = UiText.tip("The next part to run here skips the normal checks: a big familiarity gain if it works, but a miss destroys the part.")
	_push_through_check.toggled.connect(_on_push_through_toggled)
	content.add_child(_push_through_check)

	_batch_row = HBoxContainer.new()
	_batch_row.add_theme_constant_override("separation", 6)
	content.add_child(_batch_row)
	var caption := UiKit.label("Batch size", UiKit.FONT_BODY, "text_dim")
	caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_batch_row.add_child(caption)
	_batch_spin = SpinBox.new()
	_batch_spin.add_theme_font_size_override("font_size", UiKit.FONT_BODY)
	_batch_spin.get_line_edit().add_theme_font_size_override("font_size", UiKit.FONT_BODY)
	_batch_spin.value_changed.connect(_on_batch_size_changed)
	_batch_row.add_child(_batch_spin)


func _build_lists() -> void:
	_inventory_header = UiKit.section("Transfer Inventory", "transfer")
	content.add_child(_inventory_header)
	_inventory_list = VBoxContainer.new()
	_inventory_list.add_theme_constant_override("separation", 3)
	content.add_child(_inventory_list)
	_tech_header = UiKit.section("Technicians", "role_technician")
	content.add_child(_tech_header)
	_tech_list = VBoxContainer.new()
	_tech_list.add_theme_constant_override("separation", 3)
	content.add_child(_tech_list)


# ---------------------------------------------------------------------------
# Open / close / input
# ---------------------------------------------------------------------------

## Called by main.gd when a station on the floor (or the Board) is tapped.
func open_for(station: Station) -> void:
	_station = station
	panel.visible = true
	backdrop.visible = true
	_selected_rack_index = -1
	_show_familiarity_detail = false
	_pressed_rack_index = -1
	_long_press_fired = false
	_defect_signature = ""
	_selected_signature = ""
	_inventory_signature = "-"
	MenuLayout.reset(panel)
	(panel.get_node("Scroll") as ScrollContainer).scroll_vertical = 0
	_refresh_elapsed = 0.0
	_refresh()
	opened.emit()


## Public - main.gd calls this on Escape and when another menu opens.
func close() -> void:
	panel.visible = false
	backdrop.visible = false
	_station = null


func _on_backdrop_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		close()


func _process(delta: float) -> void:
	if not panel.visible or _station == null:
		return
	_update_long_press(delta)
	_refresh_elapsed += delta
	if _refresh_elapsed < REFRESH_INTERVAL or _click_in_progress():
		return
	_refresh_elapsed = 0.0
	_refresh()


## A rebuild landing between a button's press and release would eat the
## click - every refresh path skips itself while the pointer is down.
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
		_select_rack_slot(index, false)
	_pressed_rack_index = -1


func _update_long_press(delta: float) -> void:
	if _pressed_rack_index < 0 or _long_press_fired:
		return
	_press_elapsed += delta
	if _press_elapsed < LONG_PRESS_SECONDS:
		return
	_long_press_fired = true
	_select_rack_slot(_pressed_rack_index, true)


func _select_rack_slot(index: int, with_familiarity: bool) -> void:
	if _station == null or index >= _station.queue_rack.size():
		return
	# Tapping the selected slot again deselects it.
	if index == _selected_rack_index and not with_familiarity and not _show_familiarity_detail:
		_selected_rack_index = -1
	else:
		_selected_rack_index = index
	_show_familiarity_detail = with_familiarity
	_selected_signature = ""
	_refresh.call_deferred()


# ---------------------------------------------------------------------------
# Refresh (in place)
# ---------------------------------------------------------------------------

func _refresh() -> void:
	if _station == null:
		return
	var is_automatic := _station.station_type == Station.StationType.AUTOMATIC
	var staffed := not _station.assigned_technicians.is_empty()

	# Header.
	_sprite.texture = UiKit.station_texture(_station)
	_title.text = "%s  T%d" % [_station.station_name, _station.current_tier]
	_status.text = _station.get_overview_status()
	_progress.value = _station.progress_fraction()
	UiKit.set_bar_color(_progress, _station.progress_color_key())
	var left := _station.display_time_left()
	_time.text = Station.short_time(left) if left > 0.0 else ""

	_refresh_defect_strip()
	_refresh_rack(is_automatic)
	_refresh_actions(is_automatic, staffed)
	_refresh_selected()

	_push_through_check.visible = GameData.PUSH_THROUGH_ELIGIBLE_STATIONS.has(_station.station_id)
	if _push_through_check.visible:
		_push_through_check.set_pressed_no_signal(_station.push_through_armed)
	_batch_row.visible = not is_automatic and _station.station_type == Station.StationType.BATCHED and not staffed
	if _batch_row.visible:
		_batch_spin.min_value = 1
		_batch_spin.max_value = maxi(_station.batch_cap, 1)
		_batch_spin.set_value_no_signal(_station.batch_size)
		_batch_spin.editable = _station.current_state == Station.State.IDLE

	_refresh_inventory()
	_refresh_technicians(is_automatic)


## Every flagged part physically at this station (parallel/batch stations
## can hold several).
func _defective_parts_here() -> Array[Part]:
	var parts: Array[Part] = []
	if _station.uses_parallel_runs():
		for run in _station.shelling_active_parts:
			if run.part.is_defective:
				parts.append(run.part)
		for part in _station.shelling_ready_parts:
			if part.is_defective:
				parts.append(part)
	elif _station.current_part != null and _station.current_part.is_defective:
		parts.append(_station.current_part)
	return parts


func _refresh_defect_strip() -> void:
	var parts := _defective_parts_here()
	_defect_card.visible = not parts.is_empty()
	var signature := ""
	for part in parts:
		signature += "%d:%d:%s," % [part.part_id, part.defect_category, GameData.can_afford_with_gems(GameData.REDESIGN_COST)]
	if signature == _defect_signature:
		return
	_defect_signature = signature
	MenuLayout.clear(_defect_actions)
	if parts.is_empty():
		return
	var first := parts[0]
	_defect_label.text = "Defective part #%d - %s" % [first.part_id, GameData.DEFECT_CATEGORY_LABEL[first.defect_category]]
	if parts.size() > 1:
		_defect_label.text += " (+%d more)" % (parts.size() - 1)
	for part in parts:
		_add_defect_fix_buttons(_defect_actions, part)


func _refresh_rack(is_automatic: bool) -> void:
	var rack := _station.queue_rack
	_rack_title.text = "Queue Rack (%d/%d)" % [rack.size(), _station.rack_capacity]
	_rack_title.get_parent().visible = not is_automatic
	for i in RACK_SLOT_COUNT:
		var slot := _rack_slots[i]
		if i < rack.size():
			var part := rack[i]
			slot.disabled = false
			slot.icon = UiIcons.get_icon(UiKit.part_icon(GameData.geometry_name_for_part(part)))
			slot.tooltip_text = UiText.tip(_part_detail_text(part))
			UiKit.set_button_kind(slot, "danger" if part.is_defective else ("primary" if i == _selected_rack_index else "neutral"))
			slot.modulate = Color.WHITE
		elif i < _station.rack_capacity:
			slot.disabled = true
			slot.icon = null
			slot.tooltip_text = ""
			UiKit.set_button_kind(slot, "neutral")
			slot.modulate = Color.WHITE
		else:
			# Past this station's capacity: locked until the rack is upgraded.
			slot.disabled = true
			slot.icon = UiIcons.get_icon("act_lock")
			slot.tooltip_text = ""
			UiKit.set_button_kind(slot, "neutral")
			slot.modulate = Color(1, 1, 1, 0.45)
	if _selected_rack_index >= rack.size():
		_selected_rack_index = -1
		_show_familiarity_detail = false


func _refresh_actions(is_automatic: bool, staffed: bool) -> void:
	_queue_button.visible = (not is_automatic and not staffed
		and _station.is_pipeline_entry and _station.current_state == Station.State.IDLE)
	if _queue_button.visible:
		# can_start_new_work() blocks a print when the next station has no
		# room or too many defects are unaddressed - say so, don't just hide.
		_queue_button.disabled = not _station.can_start_new_work() or not GameData.has_print_order()
		_queue_button.text = "Start print" if not _queue_button.disabled else "Blocked"
		_queue_button.tooltip_text = UiText.tip("Start the next queued print order here." if not _queue_button.disabled
			else ("No print orders - queue parts in Contracts." if not GameData.has_print_order() else "Blocked - clear the backlog downstream first."))

	# Collect whenever no technician is HERE to route it - staffed or not.
	_collect_button.visible = (not is_automatic and _station.current_state == Station.State.READY
		and (not staffed or not _station.is_technician_present()))
	if _collect_button.visible:
		_collect_button.text = "Collect"
		_collect_button.tooltip_text = UiText.tip("Move the finished part to Awaiting Transfer." if not staffed
			else "The technician is elsewhere - move the finished part to Awaiting Transfer yourself.")

	_start_cycle_button.visible = _station.can_start_batch_cycle_manually()
	if _start_cycle_button.visible:
		var loaded := mini(_station.batch_cap, _station.batch_load.size() + _station.queue_rack.size())
		_start_cycle_button.text = "Start %d/%d" % [loaded, _station.batch_cap]
		_start_cycle_button.tooltip_text = UiText.tip("Start this batch cycle with what's loaded.")

	_upgrade_button.visible = not is_automatic
	if _station.current_tier < 5:
		var cost := GameData.upgrade_cost_for_tier(_station.current_tier + 1)
		_upgrade_button.text = "Tier %d: %dg" % [_station.current_tier + 1, cost]
		_upgrade_button.disabled = not GameData.can_afford_with_gems(cost)
	else:
		_upgrade_button.text = "Max tier"
		_upgrade_button.disabled = true
	_upgrade_rack_button.visible = not is_automatic
	if _station.rack_capacity < Station.MAX_RACK_CAPACITY:
		var rack_cost := GameData.rack_upgrade_cost_for(_station.rack_capacity + 1)
		_upgrade_rack_button.text = "Rack %d: %dg" % [_station.rack_capacity + 1, rack_cost]
		_upgrade_rack_button.disabled = not GameData.can_afford_with_gems(rack_cost)
		_upgrade_rack_button.tooltip_text = UiText.tip("Room for %d parts waiting here." % (_station.rack_capacity + 1))
	else:
		_upgrade_rack_button.text = "Max rack"
		_upgrade_rack_button.disabled = true


func _refresh_selected() -> void:
	var has := _selected_rack_index >= 0 and _selected_rack_index < _station.queue_rack.size()
	_selected_card.visible = has
	if not has:
		return
	var part := _station.queue_rack[_selected_rack_index]
	var text := _part_detail_text(part)
	if _show_familiarity_detail:
		text += "\n" + _part_familiarity_breakdown_text(part)
	_selected_label.text = text
	(_selected_icon.get_child(0) as TextureRect).texture = UiIcons.get_icon(UiKit.part_icon(GameData.geometry_name_for_part(part)))
	UiKit.set_card_border(_selected_card, "bad" if part.is_defective else "gold")
	var signature := "%d:%s:%s" % [part.part_id, part.is_defective, GameData.can_afford_with_gems(GameData.REDESIGN_COST)]
	if signature != _selected_signature:
		_selected_signature = signature
		MenuLayout.clear(_selected_actions)
		_add_defect_fix_buttons(_selected_actions, part)


## Parts in Awaiting Transfer bound here, defective first. Rebuilt only
## when the set (or a part's state, or whether Insert is possible) changes.
func _refresh_inventory() -> void:
	var compatible: Array[Part] = []
	for part in GameData.held_parts:
		if GameData.next_station_id_for(part) == _station.station_id:
			compatible.append(part)
	compatible.sort_custom(func(a: Part, b: Part) -> bool:
		if a.is_defective != b.is_defective:
			return a.is_defective
		return a.part_id < b.part_id)
	_inventory_header.visible = not compatible.is_empty()
	_inventory_list.visible = not compatible.is_empty()
	(_inventory_header.get_meta("right_label") as Label).text = "%d waiting" % compatible.size()
	var signature := "%s|" % _station.can_accept_part()
	for part in compatible:
		signature += "%d:%s," % [part.part_id, part.is_defective]
	if signature == _inventory_signature:
		return
	_inventory_signature = signature
	MenuLayout.clear(_inventory_list)
	for part in compatible:
		_inventory_list.add_child(_build_inventory_row(part))


func _build_inventory_row(part: Part) -> Control:
	var box := UiKit.card("bad" if part.is_defective else "card_border")
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 2)
	box.add_child(body)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)
	body.add_child(line)
	var geometry := GameData.geometry_name_for_part(part)
	line.add_child(UiKit.icon(UiKit.part_icon(geometry)))
	var id_label := UiKit.label("#%d" % part.part_id)
	id_label.custom_minimum_size.x = 28.0
	id_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(id_label)
	var contract := GameData.get_contract(part.contract_id)
	var who := UiKit.label(contract.customer_name if contract != null else "no contract", UiKit.FONT_SMALL, "text_dim")
	who.clip_text = true
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	who.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	line.add_child(who)
	var meter := UiKit.meter(GameData.average_familiarity_stars(geometry) / 5.0, "gold", 5)
	meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	meter.tooltip_text = "Familiarity"
	line.add_child(meter)
	var insert := UiKit.button("Insert", "", "warn")
	insert.disabled = not _station.can_accept_part()
	insert.tooltip_text = UiText.tip("Put this part into %s." % _station.station_name if not insert.disabled else "%s has no room right now." % _station.station_name)
	insert.pressed.connect(_on_insert_part.bind(part))
	line.add_child(insert)
	if part.is_defective:
		var fixes := HFlowContainer.new()
		fixes.add_theme_constant_override("h_separation", 3)
		fixes.add_theme_constant_override("v_separation", 3)
		var pill := UiKit.pill(_defect_text(part), "bad")
		pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		fixes.add_child(pill)
		_add_defect_fix_buttons(fixes, part)
		body.add_child(fixes)
	return box


## One row per technician (every technician covers every station): portrait,
## name and tier, and where they are relative to this station.
func _refresh_technicians(is_automatic: bool) -> void:
	var crew: Array[Technician] = []
	for tech in _station.assigned_technicians:
		crew.append(tech)
	_tech_header.visible = not is_automatic
	_tech_list.visible = not is_automatic
	var here := 0
	for tech in crew:
		if tech.current_station_id == _station.station_id and not tech.is_traveling:
			here += 1
	(_tech_header.get_meta("right_label") as Label).text = "%d here" % here if not crew.is_empty() else "none hired"
	for tech in _tech_rows.keys().duplicate():
		if not crew.has(tech):
			MenuLayout.remove_and_free(_tech_rows[tech].box)
			_tech_rows.erase(tech)
	if crew.is_empty():
		if not _tech_rows.has(null):
			var empty := UiKit.label("No technicians yet - hire them in Team. Every technician works every station.", UiKit.FONT_SMALL, "text_dim")
			empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_tech_list.add_child(empty)
			_tech_rows[null] = {"box": empty}
		return
	if _tech_rows.has(null):
		MenuLayout.remove_and_free(_tech_rows[null].box)
		_tech_rows.erase(null)
	for tech in crew:
		var row: Dictionary = _tech_rows.get(tech, {})
		if row.is_empty():
			row = _build_tech_row(tech)
			_tech_rows[tech] = row
			_tech_list.add_child(row.box)
		_update_tech_row(row, tech)


func _build_tech_row(tech: Technician) -> Dictionary:
	var box := UiKit.card()
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 5)
	box.add_child(line)
	line.add_child(Portraits.view(Portraits.for_staff(tech), 24))
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 0)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(info)
	var name_label := UiKit.label("%s (%s)" % [tech.technician_name, tech.tier_label])
	name_label.clip_text = true
	info.add_child(name_label)
	var where := UiKit.label("", UiKit.FONT_SMALL, "text_dim")
	where.clip_text = true
	info.add_child(where)
	var state := UiKit.pill("", "good")
	state.custom_minimum_size.x = 46.0
	state.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	line.add_child(state)
	return {"box": box, "where": where, "state": state}


func _update_tech_row(row: Dictionary, tech: Technician) -> void:
	var where: Label = row.where
	var at_here := tech.current_station_id == _station.station_id and not tech.is_traveling
	if at_here:
		var role := "running it" if _station.active_worker == tech else "dropping off"
		where.text = "Here, %s" % role
		UiKit.set_pill(row.state, "Here", "good")
	elif tech.is_traveling and tech.travel_target_station_id == _station.station_id:
		where.text = "On the way here"
		UiKit.set_pill(row.state, "Coming", "gold")
	elif tech.is_traveling:
		where.text = "Walking to %s" % _display_name_for(tech.travel_target_station_id)
		UiKit.set_pill(row.state, "Away", "info")
	else:
		where.text = "At %s" % _display_name_for(tech.current_station_id)
		UiKit.set_pill(row.state, "Away", "info")
	if not tech.carried_parts.is_empty():
		where.text += " - carrying %d" % tech.carried_parts.size()


# ---------------------------------------------------------------------------
# Defect fixes (design doc Section 9 / 21.6)
# ---------------------------------------------------------------------------

## Mortar Patch (Shell Crack, only at Mold Prep - 21.4), Redesign (any
## category), and the expertise Scrap (21.6, only at high familiarity). Every
## call site passes a wrapping container (UI rule 2).
func _add_defect_fix_buttons(row: Container, part: Part) -> void:
	if not part.is_defective:
		return
	if GameData.can_mortar_patch(part) and _station.station_id == "mold_prep":
		var mortar := UiKit.button("Mortar %dg" % GameData.MORTAR_PATCH_COST, "", "warn")
		mortar.tooltip_text = UiText.tip("Patch the shell crack. Quick and reliable, but you learn nothing.")
		mortar.disabled = not GameData.can_afford_with_gems(GameData.MORTAR_PATCH_COST)
		mortar.pressed.connect(_on_fix_defect.bind(part, false))
		row.add_child(mortar)
	var redesign := UiKit.button("Redesign %dg" % GameData.REDESIGN_COST, "act_rework", "primary")
	redesign.tooltip_text = UiText.tip("Fix the root cause. Costs more, raises familiarity.")
	redesign.disabled = not GameData.can_afford_with_gems(GameData.REDESIGN_COST)
	redesign.pressed.connect(_on_fix_defect.bind(part, true))
	row.add_child(redesign)
	if GameData.can_scrap_for_expertise(part):
		var weakest := GameData.weakest_familiarity_percent(GameData.geometry_name_for_part(part))
		# The weakest-link percentage stays on the face (21.7 wants it in front
		# of the player here); the sentence lives in the tooltip.
		var scrap := UiKit.button("Scrap (%d%%)" % weakest, "act_scrap", "danger")
		scrap.tooltip_text = UiText.tip("Scrap this part - it won't meet tolerance. Weakest-link familiarity for this geometry: %d%%." % weakest)
		scrap.pressed.connect(_on_scrap_part.bind(part))
		row.add_child(scrap)


func _defect_text(part: Part) -> String:
	var label: String = GameData.DEFECT_CATEGORY_LABEL[part.defect_category]
	return "%s (escalated)" % label if part.defect_escalated else label


# ---------------------------------------------------------------------------
# Text helpers
# ---------------------------------------------------------------------------

## Everything worth knowing about a racked Part: contract, quick-glance
## familiarity, where it goes next, defect.
func _part_detail_text(part: Part) -> String:
	var contract := GameData.get_contract(part.contract_id)
	var lines: Array[String] = []
	if contract != null:
		var geometry := GameData.geometry_name_for_part(part)
		lines.append("Part #%d - %s" % [part.part_id, contract.customer_name])
		lines.append("%s, %s" % [geometry, GameData.alloy_name_for_part(part)])
		lines.append("Familiarity %d/5" % GameData.average_familiarity_stars(geometry))
	else:
		lines.append("Part #%d - no contract" % part.part_id)
	var next_id := GameData.next_station_id_for(part)
	lines.append("Next: %s" % (_display_name_for(next_id) if next_id != "" else "end of line"))
	if part.is_defective:
		lines.append("Defect: %s" % _defect_text(part))
	return "\n".join(PackedStringArray(lines))


## Section 21.7's detail view: familiarity per station, not just the average.
func _part_familiarity_breakdown_text(part: Part) -> String:
	var geometry := GameData.geometry_name_for_part(part)
	if geometry == "":
		return "Familiarity by station: no contract"
	var lines: Array[String] = ["Familiarity by station:"]
	for station_id in GameData.FAMILIARITY_TRACKED_STATIONS:
		lines.append("  %s: %d/5" % [_display_name_for(station_id), GameData.familiarity_stars_for(geometry, station_id)])
	return "\n".join(PackedStringArray(lines))


## Prefers the live Station's own name ("Printing #2") over the shared
## StationDef display name.
func _display_name_for(station_id: String) -> String:
	var station: Station = GameData.station_by_id.get(station_id)
	if station != null:
		return station.station_name
	var def := GameData.get_station(station_id)
	return def.display_name if def != null else station_id


# ---------------------------------------------------------------------------
# Actions - every one defers its refresh so the click finishes first
# ---------------------------------------------------------------------------

func _on_queue_pressed() -> void:
	if _station != null:
		_station.queue_new_part()
	_refresh.call_deferred()


func _on_collect_pressed() -> void:
	if _station != null:
		_station.collect_ready_part()
	_refresh.call_deferred()


func _on_start_cycle_pressed() -> void:
	if _station != null:
		_station.start_batch_cycle_manually()
	_refresh.call_deferred()


func _on_upgrade_pressed() -> void:
	if _station != null:
		_station.try_upgrade()
	_refresh.call_deferred()


func _on_upgrade_rack_pressed() -> void:
	if _station != null:
		_station.try_upgrade_rack()
	_refresh.call_deferred()


func _on_push_through_toggled(pressed: bool) -> void:
	if _station != null:
		_station.set_push_through_armed(pressed)


func _on_batch_size_changed(value: float) -> void:
	if _station != null:
		_station.set_batch_size(int(value))


func _on_insert_part(part: Part) -> void:
	if _station == null or not _station.can_accept_part():
		_refresh.call_deferred()
		return
	GameData.release_held_part(part)
	_station.receive_part(part)
	_refresh.call_deferred()


func _on_fix_defect(part: Part, is_redesign: bool) -> void:
	if is_redesign:
		GameData.redesign_defect(part)
	else:
		GameData.mortar_patch_defect(part)
	_defect_signature = ""
	_selected_signature = ""
	_inventory_signature = "-"
	_refresh.call_deferred()


func _on_scrap_part(part: Part) -> void:
	if GameData.scrap_part_for_expertise(part):
		if _station != null:
			_station.remove_part(part)
		GameData.release_held_part(part)
	_defect_signature = ""
	_selected_signature = ""
	_inventory_signature = "-"
	_refresh.call_deferred()
