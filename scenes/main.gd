extends Node2D

## Builds the standard shop floor: an open, room-based layout (see design doc
## Section 5, Shop Floor Layout) rather than a single horizontal strip.
## Rooms are simple bordered/colored zones for now, real room art comes later.
## Stations are still spawned entirely from GameData - this file only owns
## where things sit in the world, not station mechanics or Tier 1 numbers.

const StationScene: PackedScene = preload("res://scenes/station.tscn")

const VIEWPORT_SIZE: Vector2 = Vector2(480.0, 270.0)

# Overall floor bounds, a little outside the outermost room edges so there's
# breathing room at max zoom-out. Drives camera pan/zoom clamping.
const FLOOR_MIN: Vector2 = Vector2(0.0, 0.0)
const FLOOR_MAX: Vector2 = Vector2(1720.0, 960.0)

## The floor's real grid unit (design request, this session: "turn the game
## into more of a grid feeling so that customization of floor layout later
## on will be easy/contained"), the first real step toward design doc
## Section 5's "the floor is meant to sit on a tile grid" - stations still
## don't have an explicit multi-cell footprint yet (that's the next step,
## once the Floor Editor itself gets built), but every room boundary and
## station position is now expressed in whole GRID_CELL_SIZE units, so
## nothing about the current layout has to be re-derived or approximated
## when that footprint system lands. 20 was picked as the largest cell size
## that evenly divides every existing room/floor dimension already in place
## (the 40px margins, every room's width/height, and the full 1720x960
## floor) - a "fine" grid relative to a station's own footprint, per design
## request: most real-art stations span roughly 3-4 cells across, Burnout/
## Pour's much bigger photo sprites span around 11.
const GRID_CELL_SIZE: float = 20.0

## Camera2D.zoom in Godot works the opposite of what the names below might
## suggest at a glance: a HIGHER zoom value means MORE magnified (LESS world
## area visible), a LOWER value means zoomed further out (MORE area visible).
## Verified directly against Camera2D.get_canvas_transform() - this project
## briefly had the clamp math built on the opposite assumption, which is
## exactly what caused stations to be unreachable near one edge while
## zoomed in: half_view (how much world space is visible on each side of
## the camera) is VIEWPORT_SIZE * 0.5 / zoom, not * zoom.
## 0.25 is low enough that half_view (VIEWPORT_SIZE * 0.5 / zoom) exceeds half
## of FLOOR_MAX in both axes (1720x960 floor bounds below), so at max zoom-out
## the whole floor fits on screen at once and _clamp_camera_position() centers
## it automatically, rather than just showing "most of" it.
const MIN_ZOOM: float = 0.25   # zoomed out - the whole floor visible at once
const MAX_ZOOM: float = 2.0   # zoomed in - close look at a single station
const DEFAULT_ZOOM: float = 1.0
const ZOOM_STEP: float = 1.1

## A left click/tap that moves less than this many screen pixels between
## press and release counts as a station tap rather than a camera drag.
## 8px (a first guess) turned out too tight - real clicks routinely drift
## several pixels even when the user means to click cleanly.
const CLICK_MOVE_THRESHOLD: float = 24.0

## At MAX_ZOOM (most magnified), station sprites render at this fraction of
## their normal size - stations felt oversized zoomed all the way in.
## Scales up to 1.0 (normal) at DEFAULT_ZOOM and stays there below it.
const MAX_ZOOM_SPRITE_SCALE: float = 0.75

## Station Name/Status labels and room labels are rendered screen-space, not
## as world-space children of the zoomable camera (design request, this
## session: "when you zoom out i cant tell what the stations are and what
## the text says unless i am extremely close up"). Two earlier approaches
## were tried and rejected before this one: shrinking naturally with the
## camera (illegible past a certain zoom-out), and counter-scaling world-
## space Labels back up to compensate (still soft/blurry - magnifying an
## already-small rasterized glyph via Control.scale doesn't add back detail
## that was never rasterized at that size, and at MIN_ZOOM neighboring
## stations' labels visibly ran into each other). Rendering in a screen-
## space CanvasLayer (see FloorLabels below) sidesteps both: text is always
## drawn at native pixel-font resolution regardless of camera zoom, so it's
## never blurry - the only remaining problem is stations that are visually
## close together on screen (whether because they're physically close, or
## because the camera is zoomed way out) getting label text that would
## overlap. See _update_floor_labels() for how that's handled.
const FLOOR_LABEL_OFFSET: Vector2 = Vector2(-20.0, 66.0) # matches station.tscn's NameLabel top-left, in station-local space

# Room zones: rect (x, y, width, height), fill color, border color, label.
# Colors loosely follow the Art Style section's room palettes.
#
# Pinwheel layout, this session's redesign of the earlier "four 480x300
# corners around a 680x280 center hub" version (design request: "make the
# rooms surrounding the pour room in the center expand and touch each other
# meeting at the middle point"). The old corner rooms only ever touched the
# center hub at single diagonal points, never each other - four true
# rectangles now wrap pinwheel-style around a small central Pour Room
# square, each one sharing a real edge segment with both of its neighbors,
# and every one of those shared segments starts right at a corner of the
# central square - i.e. at "the middle point." Each room is still a plain
# rectangle (not an L-shape) - the classic "4 rectangles + 1 square tile a
# bigger rectangle" construction - so the existing rect-based zone/tile
# system (ZONES, _zone_index_for_cell(), _edge_tile_for()) needed no new
# cases, just new numbers. Every old STATION_POSITIONS entry already falls
# inside its room's new (larger) bounds without needing to move - verified
# below and with a headless test - since each new room is a strict superset
# of its old rect. Floor bounds (FLOOR_MIN/FLOOR_MAX) are UNCHANGED; the
# pinwheel's own center (860, 480) is both the geometric center of the full
# 1720x960 floor and the exact midpoint of the 40px-inset margins on every
# side, so nothing needed re-deriving from scratch.
const PRINT_ROOM := Rect2(40, 40, 960, 300)             # top arm
const SHELLING_ROOM := Rect2(1000, 40, 680, 580)        # right arm
const FURNACE_ROOM := Rect2(720, 620, 960, 300)         # bottom arm
const POST_PROCESSING_ROOM := Rect2(40, 340, 680, 580)  # left arm
## The small central island every arm above wraps around - still named
## POUR_ROOM in code (Pour is the one real Station there today) even though
## its on-floor label reads "VIM Bay"; GameData's own StationDef.room_name
## for Pour stays the unrelated string "Pour Room" (used for Overview/Staff
## grouping elsewhere), so this floor label was never tied to that anyway.
## Sized 280x280 - plenty for the single Pour station, with room to spare
## for the still-unbuilt "Air Melter" idea from the same design conversation.
const POUR_ROOM := Rect2(720, 340, 280, 280)

## Every cell of the floor's continuous tile grid that isn't inside one of
## the 5 room rects above gets tinted this color instead (see
## _zone_index_for_cell()) - the whole floor is one tiled surface, this is
## just the "hallway" zone's own tint, not a separate background layer.
## Since the pinwheel's 4 arms plus the central island now tile the entire
## floor (margins aside), there's no hallway "between" rooms left at all -
## this only ever shows up in the 40px margin ring around the outside.
const HALLWAY_FILL := Color(0.7, 0.7, 0.68)
const SHELLING_FILL := Color(0.87, 0.8, 0.66)
const SHELLING_BORDER := Color(0.65, 0.55, 0.4)
const PRINT_FILL := Color(0.87, 0.93, 0.97)
const PRINT_BORDER := Color(0.55, 0.7, 0.85)
const FURNACE_FILL := Color(0.85, 0.5, 0.35)
const FURNACE_BORDER := Color(0.6, 0.25, 0.15)
const POUR_FILL := Color(0.95, 0.78, 0.25)
const POUR_BORDER := Color(0.7, 0.45, 0.1)
const POST_FILL := Color(0.78, 0.81, 0.85)
const POST_BORDER := Color(0.5, 0.55, 0.6)

# Hand-placed per station, since each room now has its own footprint instead
# of one shared horizontal spacing rule. Keyed by GameData station id.
# "printing" is deliberately absent - it's spawned as N independent purchasable
# instances now (design doc Section 21.2), positioned by _printer_position()
# below instead of a single fixed spot. Deplate is gone entirely (Section
# 21.3); Clean, Scan, Patching now share printing's old row/column area,
# Mold Prep sits alongside Burnout in the Furnace Room (Section 21.4/21.5).
# Every position below predates this session's pinwheel room-rect rework
# and was kept as-is rather than re-centered - each room only ever grew
# (every new room rect is a strict superset of its old one), so every one
# of these still lands comfortably inside its own room, just no longer
# centered in it the way it once was. "pour" is the one exception, moved to
# the new small POUR_ROOM island's own center.
const STATION_POSITIONS := {
	"shelling": Vector2(1300, 160),
	"pour_cup_attach": Vector2(1480, 160),
	"clean": Vector2(100, 260),
	"uv_cure": Vector2(220, 260),
	"scan": Vector2(340, 260),
	"patching": Vector2(460, 260),
	"burnout": Vector2(1300, 720),
	"mold_prep": Vector2(1480, 720),
	"pour": Vector2(860, 480), # re-centered on the new, smaller POUR_ROOM island
	"deshell": Vector2(120, 720),
	"abrasive_blast": Vector2(280, 720),
	"ship": Vector2(440, 720),
	"grinding": Vector2(600, 720), # new this session, room to spare on the same row
}

## Printers sit in their own row within the Print Room (top of the area
## Clean/UV Cure/Scan/Patching's row sits below), spaced out so buying more
## (up to the factory level cap - see GameData.buy_printer()) has somewhere
## to go without overlapping. A formula rather than one fixed position per id
## since the number of owned printers is a runtime purchase, not fixed data.
const PRINTER_ROW_Y: float = 100.0 # nudged from 110 to land exactly on a GRID_CELL_SIZE (20) multiple
const PRINTER_ROW_START_X: float = 100.0
const PRINTER_ROW_SPACING_X: float = 140.0

func _printer_position(printer_index: int) -> Vector2:
	return Vector2(PRINTER_ROW_START_X + printer_index * PRINTER_ROW_SPACING_X, PRINTER_ROW_Y)

## Real technician sprites now live here in world space (not as a child of
## any one Station - see resources/technician.gd's WALK_SPEED-based
## movement), positioned every frame straight from Technician.current_position
## so a technician visibly walks the real distance between two stations
## instead of snapping or following an abstract timer.
const TECHNICIAN_TEXTURE: Texture2D = preload("res://assets/sprites/technician_L1.png")
const TECHNICIAN_SCALE: float = 0.032
## Small offset from the station's exact anchor point so the technician
## doesn't render dead-center on top of the station sprite.
const TECHNICIAN_SPRITE_OFFSET: Vector2 = Vector2(100.0, 32.0)

@onready var camera: Camera2D = $Camera2D
@onready var currency_label: Label = $HUD/CurrencyLabel
@onready var gems_label: Label = $HUD/GemsLabel
@onready var reputation_label: Label = $HUD/ReputationLabel
@onready var factory_level_label: Label = $HUD/FactoryLevelLabel
@onready var floor_labels_layer: CanvasLayer = $FloorLabels
@onready var station_detail_menu: StationDetailMenu = $StationDetailMenu
@onready var overview_overlay: OverviewOverlay = $OverviewOverlay
@onready var awaiting_transfer_overlay: AwaitingTransferOverlay = $AwaitingTransferOverlay
@onready var contracts_overlay: ContractsOverlay = $ContractsOverlay
@onready var staff_overlay: StaffOverlay = $StaffOverlay
@onready var printers_overlay: PrintersOverlay = $PrintersOverlay
@onready var dashboard_overlay: Dashboard = $DashboardOverlay
@onready var settings_overlay: SettingsOverlay = $SettingsOverlay

## Every top-level overlay panel that should ever be mutually exclusive with
## every other one - populated in _ready() once all the @onready vars above
## are valid. Deliberately untyped (not Array[OverlayBase]): station_detail_menu
## isn't an OverlayBase (see that class's own comment for why - it opens via
## open_for(station) rather than a persistent toggle button), but it still
## duck-types the same panel/close()/opened shape every OverlayBase subclass
## does, so it belongs in the same exclusivity/freeze/Escape handling below.
## Introduced this session when the entry-point split (one button per
## category instead of tabs bundled under Menu/Shop) took the overlay count
## from 3 to 7 - hand-writing every pairwise opened.connect() close-the-others
## block at that count would have been both a lot of near-identical
## boilerplate and an easy place to accidentally miss a pair.
var _overlays: Array = []

var _dragging: bool = false
var _press_screen_position: Vector2 = Vector2.ZERO
var _stations_by_id: Dictionary = {}
var _technician_sprites: Dictionary = {} # Technician -> Sprite2D

## Real per-finger touch tracking (index -> last known screen position), used
## specifically to recognize a genuine two-finger pinch on an actual mobile
## touchscreen (bug fix: "when i remote deploy the game on my phone i cant
## zoom"). InputEventMagnifyGesture (handled in _unhandled_input() below) is
## NOT synthesized from a touchscreen pinch - Godot only generates it from a
## desktop trackpad's own native gesture recognizer (e.g. macOS), so relying
## on it alone left pinch-to-zoom completely non-functional on a real phone
## export, even though wheel-zoom (and a desktop trackpad, if one were ever
## used to test) both worked fine. A real touchscreen instead sends
## per-finger InputEventScreenTouch/InputEventScreenDrag events, which is
## what this dictionary tracks by index to detect a second finger joining.
var _touch_points: Dictionary = {} # touch index -> Vector2 position
var _pinch_last_distance: float = 0.0

## Screen-space room name labels (FloorLabels layer) - world_position is the
## fixed world point each one anchors to (rooms don't move, but their screen
## position still needs recomputing every frame since the camera does).
class RoomFloorLabel:
	var label: Label
	var world_position: Vector2

var _room_floor_labels: Array[RoomFloorLabel] = []

## Screen-space station Name+Status labels (FloorLabels layer), station_id ->
## Label - mirrors Station.name_label/status_label's own text (still computed
## by station.gd exactly as before) into a label that renders here instead,
## so the underlying status logic didn't need to change at all, just where
## it's drawn. See _update_floor_labels().
var _station_floor_labels: Dictionary = {}


func _ready() -> void:
	_build_floor()
	_spawn_stations()
	_setup_camera()

	overview_overlay.station_by_id = _stations_by_id
	awaiting_transfer_overlay.station_by_id = _stations_by_id
	staff_overlay.station_by_id = _stations_by_id
	dashboard_overlay.station_by_id = _stations_by_id
	GameData.station_by_id = _stations_by_id

	GameData.currency_changed.connect(_on_currency_changed)
	_on_currency_changed(GameData.currency)
	# Second "harder to get" currency (this session, design request: "there
	# will be an additional type of currency like the diamond").
	GameData.gems_changed.connect(_on_gems_changed)
	_on_gems_changed(GameData.gems)
	GameData.reputation_changed.connect(_on_reputation_changed)
	_on_reputation_changed(GameData.reputation)
	# Design request (this session): "i want to be able to see my factory
	# level, currency, and reputation" - factory_progress_changed already
	# existed for the Printers overlay's own EXP readout (see GameData), this
	# just gives the floor HUD a listener too.
	GameData.factory_progress_changed.connect(func(): _on_factory_progress_changed())
	_on_factory_progress_changed()

	# See ThemeManager's own header comment: the HUD labels are direct
	# CanvasLayer children too, so they need their own .theme set directly -
	# Window.theme alone never reaches them.
	ThemeManager.theme_changed.connect(func(_choice): _apply_hud_theme())
	_apply_hud_theme()

	# Bug fix (originally this session's split of one bundled Menu/Shop panel
	# into individual per-category overlays, later generalized): "the shop
	# button is over different menu screens" / "when i select a station the
	# button bugs out a little bit." Nothing previously stopped more than one
	# overlay being open at once - a station tap opened StationDetailMenu
	# without closing a still-open overlay underneath, and since every
	# overlay is a separate top-level CanvasLayer, a background overlay's
	# persistent toggle button could render on top of (or visually collide
	# with) whichever popped open on top of it. Each overlay emits opened()
	# the moment it opens - close every other one in response so exactly one
	# is ever visible. Generic over _overlays rather than one hardcoded
	# .connect() block per pair (see that array's own comment for why).
	_overlays = [
		overview_overlay, awaiting_transfer_overlay, contracts_overlay,
		staff_overlay, printers_overlay, dashboard_overlay, settings_overlay,
		station_detail_menu,
	]
	for overlay in _overlays:
		overlay.opened.connect(_on_overlay_opened.bind(overlay))


func _on_overlay_opened(opened_overlay: Node) -> void:
	for overlay in _overlays:
		if overlay != opened_overlay:
			overlay.close()


func _process(_delta: float) -> void:
	_sync_technician_sprites()
	_update_floor_labels()


## Ensures every hired technician has a world-space Sprite2D (creating one
## the first time a new hire shows up in GameData.technicians) and keeps its
## position/visibility synced every frame straight from the technician's own
## real current_position - not gated behind the technician_updated signal,
## since that only fires on discrete transitions and position needs to move
## smoothly every frame while someone's mid-walk.
func _sync_technician_sprites() -> void:
	for tech: Technician in GameData.technicians:
		var sprite: Sprite2D = _technician_sprites.get(tech)
		if sprite == null:
			sprite = Sprite2D.new()
			sprite.texture = TECHNICIAN_TEXTURE
			sprite.scale = Vector2(TECHNICIAN_SCALE, TECHNICIAN_SCALE)
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
			add_child(sprite)
			_technician_sprites[tech] = sprite
		sprite.visible = tech.current_station_id != "" or tech.is_traveling
		sprite.position = tech.current_position + TECHNICIAN_SPRITE_OFFSET


## Screen-space room/station labels (see FLOOR_LABEL_OFFSET's const comment
## for why they're not simple world-space children of the camera anymore).
## Runs every frame - screen position depends on both pan and zoom, not just
## zoom, so this can't be limited to zoom-change events the way the old
## sprite-scale/label-visibility split could be. Two passes: first place
## every room label (there are only a handful, spread across the floor, so
## they always win any contest and get shown), then every station label in
## a stable dictionary-insertion order, hiding any whose text would overlap
## something already accepted this frame. A hidden label isn't lost
## information, it's one tap away via the Menu Overlay's Overview tab or
## opening the station directly.
func _update_floor_labels() -> void:
	var canvas_transform: Transform2D = get_viewport().get_canvas_transform()
	var accepted_rects: Array[Rect2] = []

	for entry: RoomFloorLabel in _room_floor_labels:
		_place_and_maybe_show_label(entry.label, canvas_transform * entry.world_position, accepted_rects)

	for id: String in _stations_by_id.keys():
		var station: Station = _stations_by_id[id]
		var label: Label = _station_floor_labels.get(id)
		if label == null:
			continue
		var status_text: String = station.status_label.text
		label.text = "%s\n%s" % [station.name_label.text, status_text] if status_text != "" else station.name_label.text
		var world_pos: Vector2 = station.position + FLOOR_LABEL_OFFSET
		_place_and_maybe_show_label(label, canvas_transform * world_pos, accepted_rects)


## Shared by the room/station passes above: positions label at screen_pos,
## computes its current content rect there, and shows it only if that rect
## is on-screen and doesn't overlap anything already accepted this frame
## (accepted_rects is shared and mutated across both passes, rooms-then-
## stations, so a room label always wins any contest against a station's,
## and an earlier station in iteration order always wins against a later
## one). A label whose rect overlaps something already shown is hidden
## rather than drawn misaligned on top of it - readable text beats cramming
## everything on screen at once.
func _place_and_maybe_show_label(label: Label, screen_pos: Vector2, accepted_rects: Array[Rect2]) -> void:
	label.position = screen_pos
	var rect := Rect2(screen_pos, label.get_minimum_size())
	var on_screen := rect.position.x + rect.size.x >= 0.0 and rect.position.y + rect.size.y >= 0.0 \
		and rect.position.x <= VIEWPORT_SIZE.x and rect.position.y <= VIEWPORT_SIZE.y
	if not on_screen:
		label.visible = false
		return
	for other in accepted_rects:
		if rect.intersects(other):
			label.visible = false
			return
	label.visible = true
	accepted_rects.append(rect)


func _on_currency_changed(new_amount: int) -> void:
	currency_label.text = "Currency: %dg" % new_amount
	# Wage debt (GameData._process_wages() can push currency negative when
	# payroll can't be covered) needs a visible signal beyond the number
	# itself going negative - easy to miss at a glance otherwise.
	if new_amount < 0:
		currency_label.add_theme_color_override("font_color", Color(0.85, 0.2, 0.2))
	else:
		currency_label.remove_theme_color_override("font_color")


func _on_gems_changed(new_amount: int) -> void:
	gems_label.text = "Gems: %d" % new_amount


func _on_reputation_changed(new_amount: int) -> void:
	reputation_label.text = "Reputation: %d" % new_amount


func _on_factory_progress_changed() -> void:
	factory_level_label.text = "Factory Level: %d" % GameData.factory_level


func _apply_hud_theme() -> void:
	var theme: Theme = ThemeManager.get_current_theme_resource()
	currency_label.theme = theme
	gems_label.theme = theme
	reputation_label.theme = theme
	factory_level_label.theme = theme


func _build_floor() -> void:
	# One continuous tiled floor across the whole 1720x960 bounds (design
	# request, this session: "i want the factory to act as all one big shop
	# floor with the designated zones but the tileset across the entire
	# floor so theres no dead areas" - the previous per-room-only tiling left
	# the hallway between rooms as flat dead space). Zones are still clearly
	# outlined - direct follow-up feedback: "it doesnt have to all be 1 tile
	# you can still outline the different zones" - but the outline is now
	# real tile art (the same accent-lined edge/corner tiles used at the
	# outer floor boundary) drawn along each room's own perimeter cells, tinted
	# to that room's palette, rather than a flat ColorRect line on top of the
	# tiles. See _build_full_floor_tiles()/_edge_tile_for() below.
	_build_full_floor_tiles()
	_add_room_label(PRINT_ROOM, "Print Room")
	_add_room_label(SHELLING_ROOM, "Shelling Room")
	_add_room_label(POST_PROCESSING_ROOM, "Post Processing Room")
	_add_room_label(FURNACE_ROOM, "Furnace Room")
	_add_room_label(POUR_ROOM, "VIM Bay")


func _add_room_label(rect: Rect2, label_text: String) -> void:
	var entry := RoomFloorLabel.new()
	entry.world_position = rect.position + Vector2(10.0, 6.0)
	entry.label = _make_floor_label(label_text)
	_room_floor_labels.append(entry)


## Real per-cell floor tiles across the entire floor, one continuous grid
## (design request, this session, replacing an earlier per-room-only version
## that left the hallway between rooms untiled). Only one tile sheet exists
## on disk (assets/sprites/floor_tiles/print_room_floor_tileset_packed.png,
## a 5x5 grid of 180x180 tiles - generic industrial floor art, not
## Print-Room-specific despite the filename). Every interior cell (room or
## hallway alike) uses the same plain tile (TILE_MAIN) - an earlier version
## of this pass used a weighted-random mix of vents/hazard stripes/markers
## for variety, but that read as cluttered/messy once actually seen on
## screen (direct feedback: "get rid of your attempt of livening the shop
## floor up it looks messy"), so it's gone. **Zone boundaries are still real
## tile art, not just a tint** - every cell along a room's own perimeter
## (not just the outer floor boundary) gets the accent-lined edge/corner
## tile instead of the plain one, tinted to that room's own palette - "you
## can still outline the different zones" doesn't require every zone to
## look identical, just the interior filler tile.
##
## One Sprite2D per grid cell (a plain Sprite2D + AtlasTexture region, the
## same mechanism every station sprite already uses), using rotation to get
## 4 sides/corners out of just two source tiles (a straight edge and a
## corner, blue accent-lined) rather than needing a separate tile per
## direction - both tiles happen to point their accent line in a direction
## that rotates cleanly in 90-degree steps to cover every other side/corner.
const ROOM_TILE_TEXTURE: Texture2D = preload("res://assets/sprites/floor_tiles/print_room_floor_tileset_packed.png")
const ROOM_TILE_SOURCE_SIZE: int = 180

## Atlas coordinates (col, row), 0-indexed, matching the 5x5 sheet - picked
## by number this session (direct request: "use tile 1 for the main floor
## sections, use tile 8 for the corners, and use tile 11 for the outlines of
## zones"; floor_tile_NN.png files on disk are numbered 1-25 row-major,
## confirmed by an exact pixel-diff match against print_room_floor_tileset_
## packed.png's own 5x5 grid - tile N is atlas coords ((N-1)%5, (N-1)/5)).
const TILE_MAIN := Vector2i(0, 0)     # tile 1 - plain bolted panel, the main/interior floor tile
const TILE_CORNER := Vector2i(2, 1)   # tile 8 - corner, accent line forming a bottom-left L by default
const TILE_EDGE := Vector2i(0, 2)     # tile 11 - straight edge, accent line on the left by default

## Every designated zone that gets its own perimeter outline and tint - the
## hallway isn't in this list, it's just whatever cell belongs to none of
## these (see _zone_index_for_cell()).
const ZONES: Array[Dictionary] = [
	{"rect": PRINT_ROOM, "fill": PRINT_FILL},
	{"rect": SHELLING_ROOM, "fill": SHELLING_FILL},
	{"rect": POST_PROCESSING_ROOM, "fill": POST_FILL},
	{"rect": FURNACE_ROOM, "fill": FURNACE_FILL},
	{"rect": POUR_ROOM, "fill": POUR_FILL},
]


## Index into ZONES a given whole-floor cell (cx, cy) falls in, or -1 for
## the hallway. Rooms don't overlap (verified elsewhere), so at most one
## ever matches.
func _zone_index_for_cell(cx: int, cy: int) -> int:
	for i in ZONES.size():
		var rect: Rect2 = ZONES[i]["rect"]
		var start_cx := int(round((rect.position.x - FLOOR_MIN.x) / GRID_CELL_SIZE))
		var start_cy := int(round((rect.position.y - FLOOR_MIN.y) / GRID_CELL_SIZE))
		var cells_wide := int(round(rect.size.x / GRID_CELL_SIZE))
		var cells_tall := int(round(rect.size.y / GRID_CELL_SIZE))
		if cx >= start_cx and cx < start_cx + cells_wide and cy >= start_cy and cy < start_cy + cells_tall:
			return i
	return -1


## Shared edge/corner/plain decision, used both for the outer floor boundary
## (against the hallway's own local_cx/local_cy == cx/cy) and for each
## room's own perimeter (against that room's local cell coordinates) - same
## rotation logic either way, just applied at a different scale.
func _edge_tile_for(local_cx: int, local_cy: int, cells_wide: int, cells_tall: int) -> Dictionary:
	var is_top := local_cy == 0
	var is_bottom := local_cy == cells_tall - 1
	var is_left := local_cx == 0
	var is_right := local_cx == cells_wide - 1

	if (is_top or is_bottom) and (is_left or is_right):
		# TILE_CORNER's own accent defaults to a bottom-left L, not top-left -
		# rotation mapping is BL=0/TL=90/TR=180/BR=270, verified against the
		# tile's actual corner-point position under Godot's rotation matrix.
		var rot := 0.0 # bottom-left, the tile's own default orientation
		if is_top and is_left:
			rot = 90.0
		elif is_top and is_right:
			rot = 180.0
		elif is_bottom and is_right:
			rot = 270.0
		return {"atlas": TILE_CORNER, "rotation": rot}
	if is_top:
		return {"atlas": TILE_EDGE, "rotation": 90.0}
	if is_bottom:
		return {"atlas": TILE_EDGE, "rotation": 270.0}
	if is_left:
		return {"atlas": TILE_EDGE, "rotation": 0.0} # left is the default orientation
	if is_right:
		return {"atlas": TILE_EDGE, "rotation": 180.0}
	return {"atlas": TILE_MAIN, "rotation": 0.0}


func _build_full_floor_tiles() -> void:
	var cells_wide := int((FLOOR_MAX.x - FLOOR_MIN.x) / GRID_CELL_SIZE)
	var cells_tall := int((FLOOR_MAX.y - FLOOR_MIN.y) / GRID_CELL_SIZE)
	var half_cell := GRID_CELL_SIZE * 0.5

	for cy in cells_tall:
		for cx in cells_wide:
			var zone_index := _zone_index_for_cell(cx, cy)
			var tint: Color
			var edge: Dictionary

			if zone_index >= 0:
				var rect: Rect2 = ZONES[zone_index]["rect"]
				tint = ZONES[zone_index]["fill"]
				var start_cx := int(round((rect.position.x - FLOOR_MIN.x) / GRID_CELL_SIZE))
				var start_cy := int(round((rect.position.y - FLOOR_MIN.y) / GRID_CELL_SIZE))
				var room_cells_wide := int(round(rect.size.x / GRID_CELL_SIZE))
				var room_cells_tall := int(round(rect.size.y / GRID_CELL_SIZE))
				edge = _edge_tile_for(cx - start_cx, cy - start_cy, room_cells_wide, room_cells_tall)
			else:
				tint = HALLWAY_FILL
				edge = _edge_tile_for(cx, cy, cells_wide, cells_tall)

			var atlas_coords: Vector2i = edge["atlas"]
			var rotation_degrees_value: float = edge["rotation"]
			var cell_position := FLOOR_MIN + Vector2(cx, cy) * GRID_CELL_SIZE + Vector2(half_cell, half_cell)

			var atlas_tex := AtlasTexture.new()
			atlas_tex.atlas = ROOM_TILE_TEXTURE
			atlas_tex.region = Rect2(
				Vector2(atlas_coords) * float(ROOM_TILE_SOURCE_SIZE), Vector2.ONE * float(ROOM_TILE_SOURCE_SIZE)
			)

			var tile := Sprite2D.new()
			tile.texture = atlas_tex
			# Centered (not top-left-anchored) specifically so rotation below
			# pivots around the cell's own center instead of swinging the
			# tile out of its cell.
			tile.position = cell_position
			tile.scale = Vector2.ONE * (GRID_CELL_SIZE / float(ROOM_TILE_SOURCE_SIZE))
			tile.rotation_degrees = rotation_degrees_value
			tile.modulate = tint
			# Same zoomed-out-pixelation fix as every other real sprite this
			# session - the tile texture also has mipmaps enabled (see its
			# own .import file).
			tile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
			add_child(tile)


func _spawn_stations() -> void:
	# "printing" is spawned specially below as N independent purchasable
	# instances (design doc Section 21.2), not from this generic loop - see
	# GameData.PIPELINE_ORDER's own comment for why it's still technically
	# present in GameData.stations (the shared Tier 1 template) despite no
	# live Station ever using that exact id.
	for def in GameData.stations:
		if def.id == "printing":
			continue
		var station := _instantiate_station(def, def.id, def.display_name)
		station.is_pipeline_entry = false
		station.position = STATION_POSITIONS.get(def.id, Vector2.ZERO)
		add_child(station)
		_register_station(def.id, station)

	for i in GameData.owned_printer_count:
		_spawn_printer(i)
	GameData.printer_purchased.connect(_on_printer_purchased)

	_wire_next_station_links()


## Called immediately (buy_printer() succeeding) rather than requiring a
## scene reload - GameData.owned_printer_count has already been raised by the
## time this fires, printer_index is that new count.
func _on_printer_purchased(new_owned_count: int) -> void:
	_spawn_printer(new_owned_count - 1)
	_wire_next_station_links()
	# A newly spawned printer starts at default sprite scale - bring it in
	# line with whatever zoom level the camera is currently at, same as
	# every other station got at _setup_camera() time. Its floor label needs
	# no equivalent catch-up call - _update_floor_labels() already picks up
	# every entry in _station_floor_labels every frame regardless of when it
	# was added.
	_apply_sprite_zoom_scale()

	# Design request, this session: "i want the print station responsibility
	# to cover all the printers not individual ones." Any technician already
	# assigned to the virtual "printing" group (GameData.assign_technician_to_printer_group())
	# needs this brand new instance added to ITS OWN assigned_technicians too -
	# that's real per-Station bookkeeping the group entry in
	# Technician.assigned_station_ids can't represent by itself.
	var new_station: Station = _stations_by_id.get("printing_%d" % new_owned_count)
	if new_station != null:
		for tech in GameData.technicians:
			if tech.assigned_station_ids.has("printing"):
				new_station.assign_technician(tech)


## printer_index is 0-based (printer_index 0 -> station id "printing_1").
func _spawn_printer(printer_index: int) -> void:
	var def := GameData.get_station("printing")
	var id := "printing_%d" % (printer_index + 1)
	var station := _instantiate_station(def, id, "%s #%d" % [def.display_name, printer_index + 1])
	station.is_pipeline_entry = true
	station.position = _printer_position(printer_index)
	add_child(station)
	_register_station(id, station)


func _instantiate_station(def: GameData.StationDef, id: String, display_name: String) -> Station:
	var station := StationScene.instantiate() as Station
	station.station_id = id
	station.station_name = display_name
	station.station_type = def.station_type
	station.current_tier = 1
	station.timer_duration = def.get_prototype_timer_seconds()
	station.batch_cap = def.tier1_batch_cap
	station.tier_sprites = _load_sprites(def.tier_sprite_paths)
	station.state_sprites = _load_sprites(def.state_sprite_paths)
	station.sprite_scale_override = def.sprite_scale_override
	return station


## Common bookkeeping for a just-added-to-the-tree Station, called from both
## _spawn_stations()'s loop and _spawn_printer() - registers it for lookup
## AND creates its screen-space floor label (see FLOOR_LABEL_OFFSET's const
## comment). The station's own world-space name_label/status_label keep
## being updated exactly as before (station.gd's business logic is
## unchanged) - they're just hidden now, since _update_floor_labels() mirrors
## their text into the screen-space label instead of letting them render
## in-world where they'd shrink/blur with camera zoom.
func _register_station(id: String, station: Station) -> void:
	_stations_by_id[id] = station
	station.name_label.visible = false
	station.status_label.visible = false
	_station_floor_labels[id] = _make_floor_label(station.station_name)


## Shared by station and room floor labels - white text with a black outline
## rather than the shared UI theme's default dark-on-parchment styling, since
## these render directly over arbitrary, unpredictable floor content (room
## fill colors, station sprites) rather than over one of the theme's own
## panels - a fixed dark text color would disappear against a dark
## background. The outline (not just a plain color) is what keeps it
## readable against light backgrounds too, without needing to know what's
## actually underneath at any given moment.
func _make_floor_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.98, 0.95, 0.88))
	label.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.03))
	label.add_theme_constant_override("outline_size", 3)
	label.visible = false # _update_floor_labels() decides visibility every frame
	floor_labels_layer.add_child(label)
	return label


## Wires every Station.next_station link - safe to call again after spawning
## a new printer mid-game (re-wiring existing links to the same values is a
## no-op). "printing" gets special handling: every printer instance's
## next_station is Clean, not a single 1:1 PIPELINE_ORDER neighbor, since
## there can be several printer instances all feeding the same next step
## (design doc Section 21.2).
func _wire_next_station_links() -> void:
	var clean_station: Station = _stations_by_id.get("clean")
	for id in GameData.printer_station_ids():
		var printer: Station = _stations_by_id.get(id)
		if printer != null:
			printer.next_station = clean_station

	for i in GameData.PIPELINE_ORDER.size() - 1:
		var id: String = GameData.PIPELINE_ORDER[i]
		if id == "printing":
			continue
		var station: Station = _stations_by_id.get(id)
		var next: Station = _stations_by_id.get(GameData.PIPELINE_ORDER[i + 1])
		if station != null and next != null:
			station.next_station = next


func _load_sprites(paths: Array[String]) -> Array[Texture2D]:
	var textures: Array[Texture2D] = []
	for p in paths:
		textures.append(load(p) as Texture2D)
	return textures


func _setup_camera() -> void:
	camera.zoom = Vector2(DEFAULT_ZOOM, DEFAULT_ZOOM)
	# Start centered on the Print Room, the largest room and first in the process.
	camera.position = _clamp_camera_position(PRINT_ROOM.get_center())
	camera.make_current()
	_apply_sprite_zoom_scale()


## Shrinks every station's sprite (and its click area, which tracks the
## sprite's live scale) a bit extra as zoom approaches MAX_ZOOM (most
## magnified), per MAX_ZOOM_SPRITE_SCALE above. Full size at DEFAULT_ZOOM
## and below.
func _apply_sprite_zoom_scale() -> void:
	var t: float = clamp((camera.zoom.x - DEFAULT_ZOOM) / (MAX_ZOOM - DEFAULT_ZOOM), 0.0, 1.0)
	var multiplier: float = lerp(1.0, MAX_ZOOM_SPRITE_SCALE, t)
	for station: Station in _stations_by_id.values():
		station.set_sprite_scale_multiplier(multiplier)


func _clamp_camera_position(target: Vector2) -> Vector2:
	# Divide, not multiply: higher zoom = more magnified = LESS world space
	# visible on each side of the camera. See the MIN_ZOOM/MAX_ZOOM comment above.
	var half_view := VIEWPORT_SIZE * 0.5 / camera.zoom
	var result := target

	if FLOOR_MAX.x - FLOOR_MIN.x <= half_view.x * 2.0:
		result.x = (FLOOR_MIN.x + FLOOR_MAX.x) * 0.5
	else:
		result.x = clamp(target.x, FLOOR_MIN.x + half_view.x, FLOOR_MAX.x - half_view.x)

	if FLOOR_MAX.y - FLOOR_MIN.y <= half_view.y * 2.0:
		result.y = (FLOOR_MIN.y + FLOOR_MAX.y) * 0.5
	else:
		result.y = clamp(target.y, FLOOR_MIN.y + half_view.y, FLOOR_MAX.y - half_view.y)

	return result


func _unhandled_input(event: InputEvent) -> void:
	# Escape closes whichever overlay is open (design request, this session) -
	# checked BEFORE the freeze-while-open return below, since that's exactly
	# when this needs to fire. ui_cancel is Godot's built-in Escape binding.
	if event.is_action_pressed("ui_cancel") and _close_topmost_overlay():
		return

	# While a popup is open, background pan/zoom/click should stay frozen -
	# without this, scroll events inside a popup's ScrollContainer that don't
	# need to actually scroll (short lists) fall through un-consumed and get
	# picked up here as camera zoom instead. Generic over _overlays (see that
	# array's own comment) rather than one hardcoded "or" per overlay.
	if _any_overlay_open():
		return

	if event is InputEventScreenTouch:
		_on_screen_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_screen_drag(event as InputEventScreenDrag)
	elif event is InputEventMouseButton:
		# Explicit cast rather than relying on the "is" check above to narrow
		# event's static type - GDScript doesn't do that narrowing here, so
		# event.position on the base InputEvent type fails to type-check.
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT:
			if mouse_event.pressed:
				_dragging = true
				_press_screen_position = mouse_event.position
			else:
				_dragging = false
				var moved: float = mouse_event.position.distance_to(_press_screen_position)
				if moved < CLICK_MOVE_THRESHOLD:
					_try_click_station(get_global_mouse_position())
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_UP and mouse_event.pressed:
			_zoom_camera(ZOOM_STEP, mouse_event.position)
		elif mouse_event.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse_event.pressed:
			_zoom_camera(1.0 / ZOOM_STEP, mouse_event.position)
	elif event is InputEventMouseMotion and _dragging:
		_pan_camera(event.relative)
	elif event is InputEventMagnifyGesture:
		# factor > 1 is a pinch-out/zoom-in gesture, which should increase
		# our zoom value now (higher = more magnified).
		var magnify_event := event as InputEventMagnifyGesture
		_zoom_camera(magnify_event.factor, magnify_event.position)


func _any_overlay_open() -> bool:
	for overlay in _overlays:
		if overlay.panel.visible:
			return true
	return false


## Closes whichever one overlay is currently open (only one is ever open at a
## time in practice, enforced by _on_overlay_opened() above). Returns whether
## anything was actually closed, so the Escape handler above knows whether to
## consider the key consumed. Generic over _overlays (see that array's own
## comment) rather than one hardcoded check per overlay.
func _close_topmost_overlay() -> bool:
	for overlay in _overlays:
		if overlay.panel.visible:
			overlay.close()
			return true
	return false


## Hit-tests every station's current click rect (in that station's local
## space, see Station.get_click_rect()) against a world-space tap position,
## opening the detail popup for whichever one contains it first.
func _try_click_station(world_pos: Vector2) -> void:
	for station: Station in _stations_by_id.values():
		var local_pos := world_pos - station.position
		if station.get_click_rect().has_point(local_pos):
			station_detail_menu.open_for(station)
			return


## Updates _touch_points on every real finger press/release. A second finger
## joining means this is now a pinch, not a single-finger pan/tap - cancel
## any in-progress _dragging state so the emulated mouse motion Godot derives
## from whichever finger drives its emulated pointer (still generated even
## with a second finger also down) doesn't fight the pinch by also panning
## the camera while it's being zoomed. Dropping back below 2 fingers just
## ends the pinch; the remaining finger (if any) resumes panning naturally
## through its own continuing relative-delta drag events, no special-casing
## needed for that transition.
func _on_screen_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_touch_points[event.index] = event.position
	else:
		_touch_points.erase(event.index)

	if _touch_points.size() >= 2:
		_dragging = false
		_pinch_last_distance = _pinch_distance()
	else:
		_pinch_last_distance = 0.0


## With exactly one finger down, this is the real per-finger equivalent of
## the mouse-drag pan below (same _pan_camera() call) - previously this
## branch panned unconditionally regardless of how many fingers were on
## screen, which meant a genuine two-finger pinch was ALSO panning the camera
## once per finger's own drag event on top of whatever zoom math got added
## here, fighting each other. With two fingers down, this is a pinch instead:
## the standard "compare current inter-finger distance to last frame's" ratio
## drives _zoom_camera() the same way a wheel tick or a desktop trackpad's
## InputEventMagnifyGesture already does, anchored to the midpoint between
## the two fingers rather than the screen center.
func _on_screen_drag(event: InputEventScreenDrag) -> void:
	_touch_points[event.index] = event.position
	if _touch_points.size() < 2:
		_pan_camera(event.relative)
		return

	var distance := _pinch_distance()
	if _pinch_last_distance > 0.0:
		_zoom_camera(distance / _pinch_last_distance, _pinch_midpoint())
	_pinch_last_distance = distance


## Only ever called with exactly 2 active touch points (see the two functions
## above) - a 3rd simultaneous finger would pick two arbitrary entries out of
## the three rather than handling a genuine 3-finger gesture, a deliberate
## simplification since nobody pinch-zooms with three fingers.
func _pinch_distance() -> float:
	var points := _touch_points.values()
	return (points[0] as Vector2).distance_to(points[1] as Vector2)


func _pinch_midpoint() -> Vector2:
	var points := _touch_points.values()
	return ((points[0] as Vector2) + (points[1] as Vector2)) * 0.5


## Deliberately NOT scaled by camera.zoom - a given drag distance moves the
## camera through the same amount of world space regardless of zoom level.
## The "correct" 1:1-cursor-tracking formula (screen_delta * zoom) was
## mathematically fine but made panning feel zoom-dependent (fast zoomed in,
## slow zoomed out), which read as broken rather than as intended behavior.
func _pan_camera(screen_delta: Vector2) -> void:
	camera.position = _clamp_camera_position(camera.position - screen_delta)


## Zooms toward anchor_screen_pos (the mouse cursor for a wheel scroll, the
## gesture's own position for a pinch) rather than the screen center, the way
## every other zoomable map/canvas app behaves - previously this only ever
## zoomed around the middle of the screen regardless of where the cursor was,
## which felt wrong when zooming in on a station off-center. Standard
## zoom-to-point trick: read which world point currently sits under the
## anchor BEFORE changing zoom, then shift the camera by however much that
## same screen position's world point moved AFTER changing zoom, so the point
## that was under the cursor is still under the cursor. Computed directly
## from camera.position/zoom (same half_view relationship
## _clamp_camera_position() already uses) rather than via
## get_global_mouse_position(), since that depends on the Camera2D's own
## canvas transform having already updated for the new zoom this same frame,
## which isn't guaranteed.
func _zoom_camera(factor: float, anchor_screen_pos: Vector2) -> void:
	var old_zoom: float = camera.zoom.x
	var new_zoom: float = clamp(old_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(new_zoom, old_zoom):
		return

	var offset_from_center := anchor_screen_pos - VIEWPORT_SIZE * 0.5
	var world_before: Vector2 = camera.position + offset_from_center / old_zoom
	var world_after: Vector2 = camera.position + offset_from_center / new_zoom

	camera.zoom = Vector2(new_zoom, new_zoom)
	camera.position = _clamp_camera_position(camera.position + (world_before - world_after))
	_apply_sprite_zoom_scale()
