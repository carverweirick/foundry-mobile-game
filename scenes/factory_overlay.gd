extends OverlayBase
class_name FactoryOverlay

## The Factory screen (design doc 27.3/27.7): "see the bottleneck, then buy
## the fix in the same place." Replaces the old Overview overlay (whose
## station-status list duplicated the Board) and the Printers overlay (a
## button that only bought printers was too narrow - 27.3).
##
## Stations tab: per-station production stats from GameData's collector
## (station_stat_summary(): average cycle time, yield, how busy it's been,
## parts per hour), with the busiest station flagged as the bottleneck, and
## Tier / Rack upgrade buttons on each row so the numbers lead straight to
## a purchase. Growth tab: the old Printers screen - factory level, EXP, the
## paid Level Up (the one place GameData.level_up_factory() is called),
## process speed, and Buy Printer.

const REFRESH_INTERVAL: float = 0.5
const HEADER_COLOR := Color(0.85, 0.64, 0.16)
const BOTTLENECK_COLOR := Color(0.88, 0.35, 0.22)
## Below this much busy time the "bottleneck" call is noise, so it's held back.
const BOTTLENECK_MIN_UTILIZATION: float = 0.25

@onready var stats_list: VBoxContainer = %StatsList
@onready var factory_exp_label: Label = %FactoryExpLabel
@onready var level_up_button: Button = %LevelUpButton
@onready var process_speed_label: Label = %ProcessSpeedLabel
@onready var printer_status_label: Label = %PrinterStatusLabel
@onready var buy_printer_button: Button = %BuyPrinterButton

## Set by main.gd right after every Station is spawned.
var station_by_id: Dictionary = {}

var _refresh_elapsed: float = 0.0
var _intro_label: Label = null


func _on_ready() -> void:
	buy_printer_button.pressed.connect(_on_buy_printer_pressed)
	level_up_button.pressed.connect(_on_level_up_pressed)
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
	var container: VBoxContainer
	var name_label: Label
	var stats_label: Label
	var tier_button: Button
	var rack_button: Button
	var station: Station = null

var _stat_rows: Dictionary = {} # station_id -> StatRow
var _room_headers: Dictionary = {} # room_name -> Label


func _refresh_stats() -> void:
	if _intro_label == null:
		_intro_label = Label.new()
		_intro_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_intro_label.text = "Busy = share of time a station spends running. The busiest one is your bottleneck - upgrade it first."
		stats_list.add_child(_intro_label)
	stats_list.move_child(_intro_label, 0)

	var bottleneck_id := _bottleneck_station_id()
	var last_room := ""
	var next_index := 1
	for id in GameData.all_real_station_ids():
		var station: Station = station_by_id.get(id)
		if station == null or station.station_type == Station.StationType.AUTOMATIC:
			continue
		var room_name: String = GameData.get_station(id).room_name
		if room_name != last_room:
			last_room = room_name
			var header: Label = _room_headers.get(room_name)
			if header == null:
				header = Label.new()
				header.add_theme_color_override("font_color", HEADER_COLOR)
				header.text = room_name
				stats_list.add_child(header)
				_room_headers[room_name] = header
			stats_list.move_child(header, next_index)
			next_index += 1

		var row: StatRow = _stat_rows.get(id)
		if row == null:
			row = _create_stat_row()
			_stat_rows[id] = row
			stats_list.add_child(row.container)
		stats_list.move_child(row.container, next_index)
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
	row.container = VBoxContainer.new()
	row.container.add_theme_constant_override("separation", 1)

	row.name_label = Label.new()
	row.container.add_child(row.name_label)

	row.stats_label = Label.new()
	row.stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.container.add_child(row.stats_label)

	# Two buttons whose text varies with tier/capacity - an HFlowContainer so
	# they wrap instead of running off the panel (CLAUDE.md UI rule 2).
	var buttons := HFlowContainer.new()
	row.container.add_child(buttons)
	row.tier_button = Button.new()
	row.tier_button.pressed.connect(_on_tier_pressed.bind(row))
	buttons.add_child(row.tier_button)
	row.rack_button = Button.new()
	row.rack_button.pressed.connect(_on_rack_pressed.bind(row))
	buttons.add_child(row.rack_button)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 4.0)
	row.container.add_child(spacer)
	return row


func _update_stat_row(row: StatRow, station: Station, is_bottleneck: bool) -> void:
	row.station = station
	var summary := GameData.station_stat_summary(station.station_id)
	row.name_label.text = "%s (Tier %d)%s" % [station.station_name, station.current_tier, "  - BOTTLENECK" if is_bottleneck else ""]
	if is_bottleneck:
		row.name_label.add_theme_color_override("font_color", BOTTLENECK_COLOR)
	else:
		row.name_label.remove_theme_color_override("font_color")

	if summary.completed == 0:
		row.stats_label.text = "No parts finished here yet"
	else:
		var parts: Array[String] = [
			"Cycle %s" % _format_duration(summary.avg_cycle_seconds),
			"Busy %d%%" % roundi(summary.utilization * 100.0),
			"%.1f/hr" % summary.per_hour,
		]
		# Yield only means something where defects can actually be rolled.
		if GameData.STATION_BASE_DEFECT_RISK.has(station.station_id) or station.station_id.begins_with("printing"):
			parts.insert(1, "Yield %d%%" % roundi(summary.yield_rate * 100.0))
		row.stats_label.text = "  ".join(parts)

	if station.current_tier < 5:
		var target := station.current_tier + 1
		var cost := GameData.upgrade_cost_for_tier(target)
		row.tier_button.text = "Tier %d: %dg" % [target, cost]
		row.tier_button.disabled = not GameData.can_afford_with_gems(cost)
	else:
		row.tier_button.text = "Max tier"
		row.tier_button.disabled = true

	if station.rack_capacity < Station.MAX_RACK_CAPACITY:
		var rack_target := station.rack_capacity + 1
		var rack_cost := GameData.rack_upgrade_cost_for(rack_target)
		row.rack_button.text = "Rack %d: %dg" % [rack_target, rack_cost]
		row.rack_button.tooltip_text = "Room for %d parts waiting at this station" % rack_target
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
# Growth tab - factory level + printers (formerly the Printers overlay)
# ---------------------------------------------------------------------------

## Reaching the EXP threshold only makes the player eligible
## (can_level_up_factory()); leveling up is a deliberate paid action that
## previews both the price and the payroll it triggers before committing.
func _refresh_growth() -> void:
	if GameData.is_factory_level_maxed():
		factory_exp_label.text = "Factory Level %d (max) - %d EXP earned" % [GameData.factory_level, GameData.factory_exp]
		level_up_button.text = "Factory Level maxed"
		level_up_button.disabled = true
	else:
		var next_level := GameData.factory_level + 1
		factory_exp_label.text = "Level %d - %d/%d EXP to Level %d (completing contracts earns EXP)" % [
			GameData.factory_level, GameData.factory_exp, GameData.factory_exp_for_level(next_level), next_level
		]
		if GameData.can_level_up_factory():
			var price := GameData.factory_level_up_price()
			var payroll := GameData.total_wage_payroll()
			level_up_button.text = "Level Up to %d (%dg + %dg payroll)" % [next_level, price, payroll]
			level_up_button.disabled = not GameData.can_afford_factory_level_up()
		else:
			level_up_button.text = "Level Up (need more EXP)"
			level_up_button.disabled = true
	process_speed_label.text = "Process speed: +%d%% from factory level" % roundi(
		(GameData.factory_process_speed_multiplier() - 1.0) * 100.0)

	printer_status_label.text = "%d/%d printers owned (cap rises with factory level)" % [
		GameData.owned_printer_count, GameData.printer_cap()]
	if GameData.can_buy_printer():
		var cost := GameData.printer_purchase_cost()
		buy_printer_button.text = "Buy Printer (%dg)" % cost
		buy_printer_button.disabled = not GameData.can_afford_with_gems(cost)
	else:
		buy_printer_button.text = "Printer cap reached - level up for more"
		buy_printer_button.disabled = true


func _on_buy_printer_pressed() -> void:
	GameData.buy_printer()
	_refresh.call_deferred()


func _on_level_up_pressed() -> void:
	GameData.level_up_factory()
	_refresh.call_deferred()
