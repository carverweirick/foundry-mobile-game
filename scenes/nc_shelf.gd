extends Node2D
class_name NcShelf

## The nonconformance shelf on the floor (design doc 28.1) - one shared rack
## in VIM Bay, beside Pour, where every defective part is quarantined. Purely
## a view of GameData.nc_shelf: the rack frame plus one box per part, red
## while it waits on a diagnosis and gold once it's diagnosed and waiting on
## the player's disposition. Tapping it (main.gd) opens the NC overlay.
## Drawn from the current StationArt set ("nc_shelf"), with one marker per
## part along the bottom; falls back to a rack drawn in code.

const SIZE := Vector2(72.0, 64.0)
const MARKER_SIZE := Vector2(8.0, 6.0)
const MAX_MARKERS := 8
const SLOTS_PER_ROW := 3
const ROWS := 2
const FRAME_COLOR := Color(0.32, 0.33, 0.36)
const SHELF_COLOR := Color(0.55, 0.56, 0.6)
const OUTLINE_COLOR := Color(0.07, 0.06, 0.05)
const UNDIAGNOSED_COLOR := Color(0.85, 0.25, 0.2)
const DIAGNOSED_COLOR := Color(0.95, 0.72, 0.2)
const CLICK_PADDING: float = 16.0

var _drawn_signature: String = ""


func _ready() -> void:
	texture_filter = StationArt.texture_filter()
	ThemeManager.station_art_changed.connect(func(_style):
		texture_filter = StationArt.texture_filter()
		queue_redraw())


func _process(_delta: float) -> void:
	# Redraw only when what's on the shelf actually changed.
	var signature := ""
	for part in GameData.nc_shelf:
		signature += "%d%s," % [part.part_id, "d" if part.nc_diagnosed else ""]
	if signature != _drawn_signature:
		_drawn_signature = signature
		queue_redraw()


func get_click_rect() -> Rect2:
	return Rect2(-SIZE * 0.5, SIZE).grow(CLICK_PADDING)


func label_text() -> String:
	var count := GameData.nc_shelf.size()
	if count == 0:
		return "NC Shelf\nEmpty"
	return "NC Shelf\n%d part%s" % [count, "" if count == 1 else "s"]


func _draw() -> void:
	var rect := Rect2(-SIZE * 0.5, SIZE)
	var art := StationArt.texture_for("nc_shelf")
	if art != null:
		var k := minf(SIZE.x / art.get_width(), SIZE.y / art.get_height())
		var size := art.get_size() * k
		draw_texture_rect(art, Rect2(rect.get_center() - size * 0.5, size), false)
		var shown := mini(GameData.nc_shelf.size(), MAX_MARKERS)
		var row_width := shown * (MARKER_SIZE.x + 2.0) - 2.0
		for i in shown:
			var part: Part = GameData.nc_shelf[i]
			var marker := Rect2(Vector2(-row_width * 0.5 + i * (MARKER_SIZE.x + 2.0), rect.end.y + 2.0), MARKER_SIZE)
			draw_rect(marker, DIAGNOSED_COLOR if part.nc_diagnosed else UNDIAGNOSED_COLOR)
			draw_rect(marker, OUTLINE_COLOR, false, 1.0)
		return
	draw_rect(rect, FRAME_COLOR)
	draw_rect(rect, OUTLINE_COLOR, false, 3.0)
	var row_height := SIZE.y / ROWS
	for row in ROWS:
		var shelf_y := rect.position.y + row_height * (row + 1) - 6.0
		draw_rect(Rect2(rect.position.x + 4.0, shelf_y, SIZE.x - 8.0, 4.0), SHELF_COLOR)
	var slot_width := (SIZE.x - 8.0) / SLOTS_PER_ROW
	var shown := mini(GameData.nc_shelf.size(), SLOTS_PER_ROW * ROWS)
	for i in shown:
		var part: Part = GameData.nc_shelf[i]
		var row := i / SLOTS_PER_ROW
		var col := i % SLOTS_PER_ROW
		var box := Rect2(
			rect.position.x + 4.0 + col * slot_width + 3.0,
			rect.position.y + row_height * (row + 1) - 6.0 - 16.0,
			slot_width - 6.0, 16.0)
		draw_rect(box, DIAGNOSED_COLOR if part.nc_diagnosed else UNDIAGNOSED_COLOR)
		draw_rect(box, OUTLINE_COLOR, false, 2.0)
