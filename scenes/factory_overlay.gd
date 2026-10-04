extends OverlayBase
class_name FactoryOverlay

## The Factory screen (design doc 27.3/27.7): "see the bottleneck, then buy
## the fix in the same place", in the "Operator Upgrade Console" style of
## the user's mockup (assets/inspo/UI/factory_UI.png).
##
## Stations tab: per-station production stats from GameData's collector
## (station_stat_summary(): average cycle time, yield, how busy it's been as
## a meter, parts per hour), grouped under room strips. The busiest station
## gets a red border and a BOTTLENECK pill, and every card carries its Tier
## and Rack upgrade buttons so the numbers lead straight to a purchase.
##
## Growth tab: three cards - Factory Level (EXP bar, the real effects of the
## next level, and the paid Level Up: the one place
## GameData.level_up_factory() is called), Process Speed, and Printers
## (owned/cap and Buy Printer).

const REFRESH_INTERVAL: float = 0.5
## Below this much busy time the "bottleneck" call is noise, so it's held back.
const BOTTLENECK_MIN_UTILIZATION: float = 0.25
const PRINTER_ICON_PATH := "res://assets/sprites/printing_station_L1.png"

## Stats columns (px) - shared by the header strip and every row.
const COL_CYCLE: float = 34.0
const COL_YIELD: float = 30.0
const COL_BUSY: float = 76.0
const COL_RATE: float = 38.0

@onready var stats_list: VBoxContainer = %StatsList
@onready var growth_content: VBoxContainer = %Content

## Set by main.gd right after every Station is spawned.
var station_by_id: Dictionary = {}

var _refresh_elapsed: float = 0.0


func _on_ready() -> void:
	_build_stats_header()
	_build_growth()
	# Purchases elsewhere (or a gems reward) can flip affordability on their
	# own, so these refresh immediately rather than waiting for the poll.
	GameData.currency_changed.connect(func(_c): _refresh_if_open.call_deferred())
	GameData.gems_changed.connect(func(_g): _refresh_if_open.call_deferred())
	GameData.factory_progress_changed.connect(func(): _refresh_if_open.call_deferred())


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


func _refresh_if_open() -> void:
	if panel.visible and not _click_in_progress():
		_refresh()


func _refresh() -> void:
	_refresh_stats()
	_refresh_growth()


# ---------------------------------------------------------------------------
# Stations tab - production stats + upgrades
# ---------------------------------------------------------------------------

## Persistent rows updated in place (same anti-"pop" pattern as the Board).
class StatRow:
	var box: PanelContainer
	var name_label: Label
	var cycle: Label
	var yield_label: Label
	var busy_meter: SegMeter
	var busy_label: Label
	var rate: Label
	var bottleneck_pill: PanelContainer
	var tier_button: Button
	var rack_button: Button
	var station: Station = null

var _stat_rows: Dictionary = {} # station_id -> StatRow
var _room_headers: Dictionary = {} # room_name -> PanelContainer
var _stats_header: Control


func _stat_columns(row: HBoxContainer, cycle: Control, yield_c: Control, busy: Control, rate: Control) -> void:
	cycle.custom_minimum_size.x = COL_CYCLE
	yield_c.custom_minimum_size.x = COL_YIELD
	busy.custom_minimum_size.x = COL_BUSY
	rate.custom_minimum_size.x = COL_RATE
	for c in [cycle, yield_c, busy, rate]:
		row.add_child(c)


func _build_stats_header() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	var intro := UiKit.label("Busy = share of time a station spends running. The busiest is your bottleneck - upgrade it first.", UiKit.FONT_SMALL, "text_dim")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(intro)
	# Inset by a card's 2px border + 4px content margin so columns line up.
	var inset := MarginContainer.new()
	inset.add_theme_constant_override("margin_left", 6)
	inset.add_theme_constant_override("margin_right", 6)
	box.add_child(inset)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	inset.add_child(row)
	var lead := UiKit.label("Station", UiKit.FONT_SMALL, "text_dim")
	lead.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lead)
	_stat_columns(row, UiKit.label("Cycle", UiKit.FONT_SMALL, "text_dim"), UiKit.label("Yield", UiKit.FONT_SMALL, "text_dim"),
		UiKit.label("Busy", UiKit.FONT_SMALL, "text_dim"), UiKit.label("Parts/hr", UiKit.FONT_SMALL, "text_dim"))
	stats_list.add_child(box)
	_stats_header = box


func _refresh_stats() -> void:
	stats_list.move_child(_stats_header, 0)
	var bottleneck_id := _bottleneck_station_id()
	var room_counts: Dictionary = {}
	for id in GameData.all_real_station_ids():
		var station: Station = station_by_id.get(id)
		if station != null and station.station_type != Station.StationType.AUTOMATIC:
			var room: String = GameData.get_station(id).room_name
			room_counts[room] = int(room_counts.get(room, 0)) + 1

	var last_room := ""
	var next_index := 1
	for id in GameData.all_real_station_ids():
		var station: Station = station_by_id.get(id)
		if station == null or station.station_type == Station.StationType.AUTOMATIC:
			continue
		var room_name: String = GameData.get_station(id).room_name
		if room_name != last_room:
			last_room = room_name
			var header: PanelContainer = _room_headers.get(room_name)
			if header == null:
				header = UiKit.section(UiKit.room_display_name(room_name), UiKit.room_icon(room_name))
				stats_list.add_child(header)
				_room_headers[room_name] = header
			var count: int = room_counts.get(room_name, 0)
			(header.get_meta("right_label") as Label).text = "%d station%s" % [count, "" if count == 1 else "s"]
			stats_list.move_child(header, next_index)
			next_index += 1

		var row: StatRow = _stat_rows.get(id)
		if row == null:
			row = _create_stat_row()
			_stat_rows[id] = row
			stats_list.add_child(row.box)
		stats_list.move_child(row.box, next_index)
		next_index += 1
		_update_stat_row(row, station, id == bottleneck_id)


## The station with the highest busy share, if any is busy enough for that
## to mean something.
func _bottleneck_station_id() -> String:
	var best_id := ""
	var best := BOTTLENECK_MIN_UTILIZATION
	for id in GameData.all_real_station_ids():
		var utilization: float = GameData.station_stat_summary(id).utilization
		if utilization > best:
			best = utilization
			best_id = id
	return best_id


func _create_stat_row() -> StatRow:
	var row := StatRow.new()
	row.box = UiKit.card()
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	row.box.add_child(body)

	# Stats line: fixed-width columns, no autowrap (UI rule 1).
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)
	body.add_child(line)
	row.name_label = UiKit.label("")
	row.name_label.clip_text = true
	row.name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(row.name_label)
	row.cycle = UiKit.label("")
	row.yield_label = UiKit.label("")
	var busy := HBoxContainer.new()
	busy.add_theme_constant_override("separation", 3)
	row.busy_meter = UiKit.meter(0.0, "good", 9)
	row.busy_meter.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	busy.add_child(row.busy_meter)
	row.busy_label = UiKit.label("")
	busy.add_child(row.busy_label)
	row.rate = UiKit.label("")
	_stat_columns(line, row.cycle, row.yield_label, busy, row.rate)

	# Upgrade buttons: their text varies with tier/capacity - HFlowContainer
	# so they wrap instead of running off the panel (UI rule 2).
	var actions := HFlowContainer.new()
	actions.add_theme_constant_override("h_separation", 4)
	actions.add_theme_constant_override("v_separation", 2)
	actions.alignment = FlowContainer.ALIGNMENT_END
	body.add_child(actions)
	row.bottleneck_pill = UiKit.pill("! BOTTLENECK", "bad")
	row.bottleneck_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	actions.add_child(row.bottleneck_pill)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(spacer)
	row.tier_button = UiKit.button("", "act_upgrade")
	row.tier_button.pressed.connect(_on_tier_pressed.bind(row))
	actions.add_child(row.tier_button)
	row.rack_button = UiKit.button("", "act_rack")
	row.rack_button.pressed.connect(_on_rack_pressed.bind(row))
	actions.add_child(row.rack_button)
	return row


func _update_stat_row(row: StatRow, station: Station, is_bottleneck: bool) -> void:
	row.station = station
	var summary := GameData.station_stat_summary(station.station_id)
	row.name_label.text = "%s  T%d" % [station.station_name, station.current_tier]
	UiKit.set_card_border(row.box, "bad" if is_bottleneck else "card_border")
	row.bottleneck_pill.visible = is_bottleneck

	var utilization: float = summary.utilization
	row.busy_meter.value = utilization
	row.busy_meter.color_key = "bad" if is_bottleneck else ("warn" if utilization >= 0.6 else "good")
	row.busy_label.text = "%d%%" % roundi(utilization * 100.0)
	UiKit.set_label_color(row.busy_label, "bad" if is_bottleneck else "text")
	if summary.completed == 0:
		row.cycle.text = "-"
		row.yield_label.text = "-"
		row.rate.text = "-"
	else:
		row.cycle.text = _format_duration(summary.avg_cycle_seconds)
		# Yield only means something where defects can actually be rolled.
		var rolls := GameData.STATION_BASE_DEFECT_RISK.has(station.station_id) or station.station_id.begins_with("printing")
		row.yield_label.text = "%d%%" % roundi(summary.yield_rate * 100.0) if rolls else "-"
		row.rate.text = "%.1f/hr" % summary.per_hour

	if station.current_tier < 5:
		var target := station.current_tier + 1
		var cost := GameData.upgrade_cost_for_tier(target)
		row.tier_button.text = "Tier %d: %dg" % [target, cost]
		row.tier_button.disabled = not GameData.can_afford_with_gems(cost)
		UiKit.set_button_kind(row.tier_button, "primary" if is_bottleneck and not row.tier_button.disabled else "neutral")
	else:
		row.tier_button.text = "Max tier"
		row.tier_button.disabled = true

	if station.rack_capacity < Station.MAX_RACK_CAPACITY:
		var rack_target := station.rack_capacity + 1
		var rack_cost := GameData.rack_upgrade_cost_for(rack_target)
		row.rack_button.text = "Rack %d: %dg" % [rack_target, rack_cost]
		row.rack_button.tooltip_text = UiText.tip("Room for %d parts waiting at this station" % rack_target)
		row.rack_button.disabled = not GameData.can_afford_with_gems(rack_cost)
	else:
		row.rack_button.text = "Max rack"
		row.rack_button.disabled = true


func _format_duration(seconds: float) -> String:
	if seconds >= 60.0:
		return "%.1fm" % (seconds / 60.0)
	return "%ds" % roundi(seconds)


func _on_tier_pressed(row: StatRow) -> void:
	if row.station != null:
		row.station.try_upgrade()
	_refresh.call_deferred()


func _on_rack_pressed(row: StatRow) -> void:
	if row.station != null:
		row.station.try_upgrade_rack()
	_refresh.call_deferred()


# ---------------------------------------------------------------------------
# Growth tab - factory level, process speed, printers
# ---------------------------------------------------------------------------

var _level_title: Label
var _exp_label: Label
var _exp_bar: ProgressBar
var _unlocks_title: Label
var _unlocks_label: Label
var _level_up_button: Button
var _speed_value: Label
var _printer_count: Label
var _printer_icons: HBoxContainer
var _buy_printer_button: Button
var _printer_note: Label


func _card_with_section(title: String, icon_name: String) -> VBoxContainer:
	var card := UiKit.card()
	growth_content.add_child(card)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	card.add_child(body)
	body.add_child(UiKit.section(title, icon_name))
	return body


func _build_growth() -> void:
	growth_content.add_theme_constant_override("separation", 6)

	# Factory level: EXP + next-level effects on the left, Level Up on the right.
	var level_body := _card_with_section("Factory Level", "factory")
	var level_row := HBoxContainer.new()
	level_row.add_theme_constant_override("separation", 6)
	level_body.add_child(level_row)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 3)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level_row.add_child(left)
	var title_row := HBoxContainer.new()
	left.add_child(title_row)
	_level_title = UiKit.label("", UiKit.FONT_TITLE)
	_level_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_level_title)
	_exp_label = UiKit.label("", UiKit.FONT_SMALL, "text_dim")
	_exp_label.size_flags_vertical = Control.SIZE_SHRINK_END
	title_row.add_child(_exp_label)
	_exp_bar = UiKit.bar("gold", 8)
	left.add_child(_exp_bar)
	_unlocks_title = UiKit.label("", UiKit.FONT_SMALL, "header_text")
	left.add_child(_unlocks_title)
	_unlocks_label = UiKit.label("", UiKit.FONT_SMALL)
	_unlocks_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_unlocks_label)
	_level_up_button = UiKit.button("", "", "warn")
	_level_up_button.custom_minimum_size = Vector2(96, 0)
	_level_up_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_level_up_button.pressed.connect(_on_level_up_pressed)
	level_row.add_child(_level_up_button)

	# Process speed.
	var speed_body := _card_with_section("Process Speed Bonus", "settings")
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 6)
	speed_body.add_child(speed_row)
	_speed_value = UiKit.label("", UiKit.FONT_TITLE, "good")
	_speed_value.custom_minimum_size.x = 44
	speed_row.add_child(_speed_value)
	var speed_note := UiKit.label("Every station's cycles run this much faster, staffed or not. Rises with each factory level.", UiKit.FONT_SMALL, "text_dim")
	speed_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	speed_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_row.add_child(speed_note)

	# Printers.
	var printer_body := _card_with_section("Printers", "room_print")
	var printer_row := HBoxContainer.new()
	printer_row.add_theme_constant_override("separation", 6)
	printer_body.add_child(printer_row)
	var counts := VBoxContainer.new()
	counts.add_theme_constant_override("separation", 0)
	printer_row.add_child(counts)
	_printer_count = UiKit.label("", UiKit.FONT_TITLE)
	counts.add_child(_printer_count)
	counts.add_child(UiKit.label("owned", UiKit.FONT_SMALL, "text_dim"))
	_printer_icons = HBoxContainer.new()
	_printer_icons.add_theme_constant_override("separation", 1)
	_printer_icons.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	printer_row.add_child(_printer_icons)
	_buy_printer_button = UiKit.button("", "", "warn")
	_buy_printer_button.custom_minimum_size = Vector2(96, 0)
	_buy_printer_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_buy_printer_button.pressed.connect(_on_buy_printer_pressed)
	printer_row.add_child(_buy_printer_button)
	_printer_note = UiKit.label("", UiKit.FONT_SMALL, "text_dim")
	_printer_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	printer_body.add_child(_printer_note)


## Reaching the EXP threshold only makes the player eligible
## (can_level_up_factory()); leveling up is a deliberate paid action that
## previews both the price and the payroll it triggers before committing.
func _refresh_growth() -> void:
	var level := GameData.factory_level
	_level_title.text = "Level %d" % level
	if GameData.is_factory_level_maxed():
		_exp_label.text = "%d EXP (max level)" % GameData.factory_exp
		_exp_bar.value = 1.0
		_unlocks_title.text = "Top factory level reached"
		_unlocks_label.text = ""
		_level_up_button.text = "Maxed"
		_level_up_button.disabled = true
	else:
		var next_level := level + 1
		var needed := GameData.factory_exp_for_level(next_level)
		_exp_label.text = "%d / %d EXP" % [GameData.factory_exp, needed]
		_exp_bar.value = clampf(float(GameData.factory_exp) / maxf(needed, 1.0), 0.0, 1.0)
		_unlocks_title.text = "Reach Level %d to unlock:" % next_level
		_unlocks_label.text = "\n".join(_next_level_effects(next_level))
		var price := GameData.factory_level_up_price()
		var payroll := GameData.total_wage_payroll()
		if GameData.can_level_up_factory():
			_level_up_button.text = "Level Up\n%dg\n+%dg payroll" % [price, payroll]
			_level_up_button.disabled = not GameData.can_afford_factory_level_up()
			_level_up_button.tooltip_text = UiText.tip("Costs %dg, then pays every hired worker's wage (%dg total) - that part can put you in debt." % [price, payroll])
		else:
			_level_up_button.text = "Level Up\n%dg\nneed EXP" % price
			_level_up_button.disabled = true
			_level_up_button.tooltip_text = UiText.tip("Finish contracts to earn Factory EXP.")
	_speed_value.text = "+%d%%" % roundi((GameData.factory_process_speed_multiplier() - 1.0) * 100.0)

	var owned := GameData.owned_printer_count
	var cap := GameData.printer_cap()
	_printer_count.text = "%d / %d" % [owned, cap]
	if _printer_icons.get_child_count() != cap:
		MenuLayout.clear(_printer_icons)
		for i in cap:
			var icon := TextureRect.new()
			icon.texture = load(PRINTER_ICON_PATH)
			icon.custom_minimum_size = Vector2(18, 22)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_printer_icons.add_child(icon)
	for i in _printer_icons.get_child_count():
		# Unbought slots read as dark silhouettes.
		(_printer_icons.get_child(i) as TextureRect).modulate = Color.WHITE if i < owned else Color(0.2, 0.2, 0.22, 0.8)
	if GameData.can_buy_printer():
		var cost := GameData.printer_purchase_cost()
		_buy_printer_button.text = "Buy Printer\n%dg" % cost
		_buy_printer_button.disabled = not GameData.can_afford_with_gems(cost)
		_printer_note.text = "More printers start more parts at once. The cap rises with factory level."
	else:
		_buy_printer_button.text = "Buy Printer\ncap reached"
		_buy_printer_button.disabled = true
		_printer_note.text = "Printer cap reached - level up the factory for more."


## Only effects that really happen at level-up (GameData.level_up_factory()
## and factory_process_speed_multiplier()).
func _next_level_effects(next_level: int) -> Array[String]:
	var effects: Array[String] = []
	effects.append("- +%d%% process speed, all stations" % roundi(GameData.FACTORY_LEVEL_SPEED_BONUS_PER_LEVEL * 100.0))
	var cap_now: int = GameData.FACTORY_LEVEL_PRINTER_CAP.get(next_level - 1, 0)
	var cap_next: int = GameData.FACTORY_LEVEL_PRINTER_CAP.get(next_level, cap_now)
	if cap_next > cap_now:
		effects.append("- Printer cap %d -> %d" % [cap_now, cap_next])
	effects.append("- +%d Gems" % GameData.FACTORY_LEVEL_UP_GEM_REWARD)
	if not GameData.technicians.is_empty():
		effects.append("- Your crew gains seniority: faster, fewer defects, higher wages")
	return effects


func _on_buy_printer_pressed() -> void:
	GameData.buy_printer()
	_refresh.call_deferred()


func _on_level_up_pressed() -> void:
	GameData.level_up_factory()
	_refresh.call_deferred()
