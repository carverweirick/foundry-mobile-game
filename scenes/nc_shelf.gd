extends Node2D
class_name NcShelf

## The nonconformance shelf on the floor (design doc 28.1) - one shared rack
## in VIM Bay, beside Pour, where every defective part is quarantined. Two
## sides (user request, 2026-10-18): the left, intake side holds
## GameData.nc_shelf - one marker per part, red while it waits on a diagnosis,
## gold once it's diagnosed and waiting on the player's disposition; the
## right, pickup side holds GameData.nc_pickup - green markers, parts sent to
## Rework or Scan waiting for a technician to carry them back to the line
## (technicians walk to pickup_point()). Purely a view; tapping it (main.gd)
## opens the NC overlay. Each side is drawn from the current StationArt set
## ("nc_shelf"), with a colored sign on top; falls back to racks drawn in code.

const SIZE := Vector2(96.0, 64.0)
const SIDE_GAP := 6.0
const SIGN_HEIGHT := 4.0
const MARKER_SIZE := Vector2(6.0, 6.0)
const MARKERS_PER_SIDE := 5
const SLOTS_PER_ROW := 2
const ROWS := 2
const FRAME_COLOR := Color(0.32, 0.33, 0.36)
const SHELF_COLOR := Color(0.55, 0.56, 0.6)
const OUTLINE_COLOR := Color(0.07, 0.06, 0.05)
const UNDIAGNOSED_COLOR := Color(0.85, 0.25, 0.2)
const DIAGNOSED_COLOR := Color(0.95, 0.72, 0.2)
const PICKUP_COLOR := Color(0.35, 0.78, 0.38)
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
	signature += "|"
	for part in GameData.nc_pickup:
		signature += "%d," % part.part_id
	if signature != _drawn_signature:
		_drawn_signature = signature
		queue_redraw()


func get_click_rect() -> Rect2:
	return Rect2(-SIZE * 0.5, SIZE).grow(CLICK_PADDING)


## Where a technician stands to collect from the pickup side (local space):
## in front of it, just below the markers.
static func pickup_point() -> Vector2:
	return Vector2(side_rect(true).get_center().x, SIZE.y * 0.5 + 10.0)


static func side_rect(pickup: bool) -> Rect2:
	var width := (SIZE.x - SIDE_GAP) * 0.5
	var x := -SIZE.x * 0.5 + (width + SIDE_GAP if pickup else 0.0)
	return Rect2(x, -SIZE.y * 0.5, width, SIZE.y)


func label_text() -> String:
	var intake := GameData.nc_shelf.size()
	var pickup := GameData.nc_pickup.size()
	if intake == 0 and pickup == 0:
		return "NC Shelf\nEmpty"
	return "NC Shelf\n%d in - %d out" % [intake, pickup]


func _draw() -> void:
	var intake_colors: Array[Color] = []
	for part in GameData.nc_shelf:
		intake_colors.append(DIAGNOSED_COLOR if part.nc_diagnosed else UNDIAGNOSED_COLOR)
	var pickup_colors: Array[Color] = []
	for part in GameData.nc_pickup:
		pickup_colors.append(PICKUP_COLOR)
	_draw_side(side_rect(false), UNDIAGNOSED_COLOR, intake_colors)
	_draw_side(side_rect(true), PICKUP_COLOR, pickup_colors)


func _draw_side(rect: Rect2, sign_color: Color, markers: Array[Color]) -> void:
	var sign := Rect2(rect.position.x + 4.0, rect.position.y, rect.size.x - 8.0, SIGN_HEIGHT)
	var body := Rect2(rect.position.x, rect.position.y + SIGN_HEIGHT + 2.0, rect.size.x, rect.size.y - SIGN_HEIGHT - 2.0)
	var art := StationArt.texture_for("nc_shelf")
	if art != null:
		var k := minf(body.size.x / art.get_width(), body.size.y / art.get_height())
		var size := art.get_size() * k
		var art_rect := Rect2(Vector2(body.get_center().x - size.x * 0.5, body.end.y - size.y), size)
		draw_texture_rect(art, art_rect, false)
		sign.position.y = art_rect.position.y - SIGN_HEIGHT - 2.0
		draw_rect(sign, sign_color)
		draw_rect(sign, OUTLINE_COLOR, false, 1.0)
		var shown := mini(markers.size(), MARKERS_PER_SIDE)
		var row_width := shown * (MARKER_SIZE.x + 2.0) - 2.0
		for i in shown:
			var marker := Rect2(Vector2(rect.get_center().x - row_width * 0.5 + i * (MARKER_SIZE.x + 2.0), rect.end.y + 2.0), MARKER_SIZE)
			draw_rect(marker, markers[i])
			draw_rect(marker, OUTLINE_COLOR, false, 1.0)
		return
	draw_rect(sign, sign_color)
	draw_rect(sign, OUTLINE_COLOR, false, 1.0)
	draw_rect(body, FRAME_COLOR)
	draw_rect(body, OUTLINE_COLOR, false, 2.0)
	var row_height := body.size.y / ROWS
	for row in ROWS:
		var shelf_y := body.position.y + row_height * (row + 1) - 5.0
		draw_rect(Rect2(body.position.x + 3.0, shelf_y, body.size.x - 6.0, 3.0), SHELF_COLOR)
	var slot_width := (body.size.x - 6.0) / SLOTS_PER_ROW
	var shown := mini(markers.size(), SLOTS_PER_ROW * ROWS)
	for i in shown:
		var row := i / SLOTS_PER_ROW
		var col := i % SLOTS_PER_ROW
		var box := Rect2(
			body.position.x + 3.0 + col * slot_width + 2.0,
			body.position.y + row_height * (row + 1) - 5.0 - 12.0,
			slot_width - 4.0, 12.0)
		draw_rect(box, markers[i])
		draw_rect(box, OUTLINE_COLOR, false, 2.0)
