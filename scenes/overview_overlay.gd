extends OverlayBase
class_name OverviewOverlay

## Standalone entry point (design request, this session: split each of the
## old Menu overlay's three tabs into its own clearly separated HUD button
## instead of bundling them as tabs under one "Menu" button). Content and
## refresh logic are otherwise unchanged from the old MenuOverlay's Overview
## tab - only how you get here changed, not what it shows.
##
## Every station across every room, its current status (idle, running with
## time remaining, or ready and waiting for collection), all in one
## simplified list instead of needing to pan the camera across the whole floor.

const REFRESH_INTERVAL: float = 0.25

@onready var overview_list: VBoxContainer = %OverviewList

## Set by main.gd right after every Station is spawned - the only way this
## overlay can see live Station nodes rather than just static StationDefs.
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
	_refresh_overview_tab()


## Bug fix (carried over from MenuOverlay): this used to _clear_list() +
## rebuild one Label per station from scratch on every 0.25s poll - a freshly
## created Control needs at least one layout pass to reach its final size, so
## tearing down and recreating 11+ Labels every 250ms caused a visible "jump"
## every single poll even though nothing structural ever actually changes
## here (the station list itself is fixed once printers are spawned; only
## each row's status text changes). One persistent Label per station id,
## created once and text-updated in place.
var _overview_rows: Dictionary = {} # station_id -> Label
var _overview_room_headers: Dictionary = {} # room_name -> Label

## Organized by room (GameData.StationDef.room_name) - a natural,
## already-existing category for a list of stations specifically.
## GameData.all_real_station_ids() already visits stations in PIPELINE_ORDER
## (printers first, then Print Room -> Shell Building -> Furnace Room ->
## Pour Room -> Post Processing), and every station within one room is
## already contiguous in that order, so a room header only needs to be
## inserted whenever the room actually changes, not per-station. Headers and
## rows are both persistent Labels reordered in place via move_child() rather
## than destroyed and recreated - reordering doesn't cause the same "pop" a
## fresh Control would.
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
				header.add_theme_color_override("font_color", Color(0.85, 0.64, 0.16))
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
			# Fixed 2-line minimum height - get_overview_status() text length
			# varies a lot (idle/running/ready, rack backlog, current-part
			# info, defect info all appended conditionally), so without this,
			# every other station's row below it in the list shifted whenever
			# one station's status happened to cross a line-wrap threshold.
			row.custom_minimum_size = Vector2(0, 40)
			overview_list.add_child(row)
			_overview_rows[id] = row
		row.text = "  %s: %s" % [station.station_name, station.get_overview_status()]
		overview_list.move_child(row, next_index)
		next_index += 1
