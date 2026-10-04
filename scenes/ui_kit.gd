class_name UiKit

## The shared look of the redesigned menus (user's inspiration mockups,
## 2026-10-03: dark cards, gold section strips with icons, colored state
## pills, segmented meters, big colored action buttons). Every menu builds
## its rows from these helpers instead of hand-styling, so they stay
## consistent - and every widget made here registers in the "uikit" group,
## so a theme switch restyles them all (restyle(), called by ThemeManager).
## Both themes are supported: colors come from palette(), never hardcoded in
## a menu.

const FONT_BODY: int = 14
const FONT_SMALL: int = 12
const FONT_TITLE: int = 18
const GROUP := "uikit"

## Colors that mean the same thing in both themes.
const GOOD := Color(0.30, 0.72, 0.32)
const WARN := Color(0.95, 0.60, 0.15)
const BAD := Color(0.84, 0.24, 0.21)
const INFO := Color(0.35, 0.62, 0.92)
const GOLD := Color(0.95, 0.72, 0.22)

const DARK := {
	"card_bg": Color(0.15, 0.15, 0.17),
	"card_border": Color(0.05, 0.05, 0.06),
	"header_bg": Color(0.22, 0.17, 0.10),
	"header_text": Color(0.95, 0.72, 0.25),
	"text": Color(0.92, 0.88, 0.80),
	"text_dim": Color(0.62, 0.60, 0.56),
	"track": Color(0.08, 0.08, 0.09),
	"neutral_bg": Color(0.20, 0.20, 0.23),
	"neutral_text": Color(0.92, 0.88, 0.80),
	"disabled_bg": Color(0.17, 0.17, 0.19),
	"disabled_text": Color(0.45, 0.44, 0.42),
}
const PARCHMENT := {
	"card_bg": Color(0.95, 0.90, 0.78),
	"card_border": Color(0.45, 0.32, 0.18),
	"header_bg": Color(0.80, 0.66, 0.44),
	"header_text": Color(0.36, 0.20, 0.06),
	"text": Color(0.20, 0.14, 0.08),
	"text_dim": Color(0.42, 0.34, 0.24),
	"track": Color(0.74, 0.66, 0.52),
	"neutral_bg": Color(0.84, 0.74, 0.56),
	"neutral_text": Color(0.20, 0.14, 0.08),
	"disabled_bg": Color(0.86, 0.80, 0.68),
	"disabled_text": Color(0.55, 0.48, 0.38),
}
const BUTTON_STATES: Array[String] = [
	"normal", "normal_mirrored", "hover", "hover_mirrored", "pressed",
	"pressed_mirrored", "hover_pressed", "hover_pressed_mirrored", "disabled",
	"disabled_mirrored", "focus",
]


static func palette() -> Dictionary:
	return DARK if ThemeManager.current_theme == ThemeManager.ThemeChoice.DARK else PARCHMENT


## A palette key, or one of the fixed semantic names (good/warn/bad/info/gold).
static func c(key: String) -> Color:
	match key:
		"good": return GOOD
		"warn": return WARN
		"bad": return BAD
		"info": return INFO
		"gold": return GOLD
	return palette().get(key, Color.MAGENTA)


## Icon for a part type, by geometry family (placeholder art until real
## per-part sprites exist).
const PART_FAMILY_ICON := {
	"Decorative": "part_pendant", "Bracket": "part_bracket", "Valve": "part_valve",
	"Housing": "part_housing", "Seal": "part_ring", "Impeller": "part_impeller",
	"Manifold": "part_valve", "Strut": "part_shaft", "Turbine": "part_turbine",
	"HotSection": "part_housing",
}


static func part_icon(geometry_name: String) -> String:
	return PART_FAMILY_ICON.get(GameData.family_for_geometry(geometry_name), "part_bracket")


## A station's own floor sprite for menus - except the generated placeholder
## box (an ImageTexture), which reads as a blank square when small; those
## use their room's icon until real art lands.
static func station_texture(station: Station) -> Texture2D:
	var texture: Texture2D = station.station_sprite.texture if station.station_sprite != null else null
	if texture == null or texture is ImageTexture:
		return UiIcons.get_icon(room_icon(GameData.get_station(station.station_id).room_name))
	return texture


## Room icons and the names players see (Pour's island reads "VIM Bay" on
## the floor; StationDef.room_name still says "Pour Room").
const ROOM_ICON := {
	"Print Room": "room_print", "Shell Building": "room_shell",
	"Furnace Room": "room_furnace", "Pour Room": "room_vim",
	"Post Processing": "room_post",
}
const ROOM_DISPLAY_NAME := {"Pour Room": "VIM Bay"}


static func room_icon(room_name: String) -> String:
	return ROOM_ICON.get(room_name, "factory")


static func room_display_name(room_name: String) -> String:
	return ROOM_DISPLAY_NAME.get(room_name, room_name)


# --- widgets ---------------------------------------------------------------

static func label(text: String, size: int = FONT_BODY, color_key: String = "text") -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	# m5x7's line height already has air in it; the default 3px extra makes
	# wrapped small text look double-spaced.
	l.add_theme_constant_override("line_spacing", 0)
	_register(l, {"type": "label", "key": color_key})
	return l


static func set_label_color(l: Label, color_key: String) -> void:
	l.get_meta("uikit").key = color_key
	_style(l)


static func icon(icon_name: String, box: int = 16) -> TextureRect:
	var t := TextureRect.new()
	t.texture = UiIcons.get_icon(icon_name)
	t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	t.custom_minimum_size = Vector2(box, box)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## An icon scaled up by a whole number (pixel art, nearest filtering) in a
## dark framed square - the part thumbnails on NC/rack cards.
static func framed_icon(icon_name: String, box: int = 32) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_register(frame, {"type": "frame"})
	var t := TextureRect.new()
	t.texture = UiIcons.get_icon(icon_name)
	t.custom_minimum_size = Vector2(box, box)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(t)
	return frame


## A card: a bordered panel holding one row/record. border_key is a palette
## or semantic color - "gold" for selected, "bad" for a bottleneck.
static func card(border_key: String = "card_border") -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	_register(p, {"type": "card", "key": border_key})
	return p


static func set_card_border(p: PanelContainer, border_key: String) -> void:
	if p.get_meta("uikit").key != border_key:
		p.get_meta("uikit").key = border_key
		_style(p)


## A section strip: icon + gold title, optional right-aligned caption.
## Returns the strip; its right caption is strip.get_meta("right_label").
static func section(text: String, icon_name: String = "", right_text: String = "") -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_register(p, {"type": "section"})
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	p.add_child(row)
	if icon_name != "":
		row.add_child(icon(icon_name, 16))
	var title := label(text, FONT_BODY, "header_text")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(title)
	var right := label(right_text, FONT_SMALL, "text_dim")
	right.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(right)
	p.set_meta("right_label", right)
	return p


## A small colored state tag ("Low", "On track", "BOTTLENECK").
static func pill(text: String, color_key: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", FONT_SMALL)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(l)
	_register(p, {"type": "pill", "key": color_key})
	return p


static func set_pill(p: PanelContainer, text: String, color_key: String) -> void:
	(p.get_child(0) as Label).text = text
	if p.get_meta("uikit").key != color_key:
		p.get_meta("uikit").key = color_key
		_style(p)


## A segmented meter (familiarity, busy %) - see SegMeter.
static func meter(value: float, color_key: String = "gold", segments: int = 8) -> SegMeter:
	var m := SegMeter.new()
	m.segments = segments
	m.color_key = color_key
	m.value = value
	return m


## A thin progress bar (cycle progress, contract progress).
static func bar(color_key: String = "gold", height: float = 6.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.min_value = 0.0
	b.max_value = 1.0
	b.custom_minimum_size = Vector2(0.0, height)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_register(b, {"type": "bar", "key": color_key})
	return b


static func set_bar_color(b: ProgressBar, color_key: String) -> void:
	if b.get_meta("uikit").key != color_key:
		b.get_meta("uikit").key = color_key
		_style(b)


## An action button. kind: "primary" (gold), "go" (green), "danger" (red),
## "neutral" (theme panel color), "warn" (orange). Compact padding, body font.
static func button(text: String, icon_name: String = "", kind: String = "neutral") -> Button:
	var b := Button.new()
	b.text = text
	if icon_name != "":
		b.icon = UiIcons.get_icon(icon_name)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", FONT_BODY)
	b.add_theme_constant_override("h_separation", 3)
	_register(b, {"type": "button", "kind": kind})
	return b


static func set_button_kind(b: Button, kind: String) -> void:
	if b.get_meta("uikit").kind != kind:
		b.get_meta("uikit").kind = kind
		_style(b)


# --- styling ---------------------------------------------------------------

static func restyle(tree: SceneTree) -> void:
	for node in tree.get_nodes_in_group(GROUP):
		_style(node)


static func _register(node: Control, meta: Dictionary) -> void:
	node.set_meta("uikit", meta)
	node.add_to_group(GROUP)
	_style(node)


static func _style(node: Node) -> void:
	if node is SegMeter:
		node.queue_redraw()
		return
	var meta: Dictionary = node.get_meta("uikit", {})
	match meta.get("type", ""):
		"label":
			node.add_theme_color_override("font_color", c(meta.key))
		"card":
			node.add_theme_stylebox_override("panel", _box(c("card_bg"), c(meta.key), 2, 4, 3))
		"frame":
			node.add_theme_stylebox_override("panel", _box(c("track"), c("card_border"), 1, 2, 2))
		"section":
			node.add_theme_stylebox_override("panel", _box(c("header_bg"), c("header_bg").darkened(0.35), 1, 4, 1))
		"pill":
			node.add_theme_stylebox_override("panel", _box(c(meta.key), c(meta.key).darkened(0.45), 1, 4, 0))
			(node.get_child(0) as Label).add_theme_color_override("font_color", Color(0.07, 0.06, 0.05))
		"bar":
			node.add_theme_stylebox_override("background", _box(c("track"), Color(0.03, 0.03, 0.03), 1, 0, 0))
			node.add_theme_stylebox_override("fill", _box(c(meta.key), Color(0.03, 0.03, 0.03), 1, 0, 0))
		"button":
			_style_button(node, meta.kind)


static func _style_button(b: Button, kind: String) -> void:
	var bg: Color
	var fg: Color
	match kind:
		"primary":
			bg = GOLD; fg = Color(0.12, 0.08, 0.03)
		"go":
			bg = GOOD.darkened(0.1); fg = Color(0.98, 0.98, 0.95)
		"danger":
			bg = BAD.darkened(0.1); fg = Color(0.98, 0.95, 0.93)
		"warn":
			bg = WARN.darkened(0.05); fg = Color(0.12, 0.08, 0.03)
		_:
			bg = c("neutral_bg"); fg = c("neutral_text")
	var border := bg.darkened(0.55)
	for state in BUTTON_STATES:
		var fill := bg
		if state.begins_with("hover") and not state.begins_with("hover_pressed"):
			fill = bg.lightened(0.12)
		elif state.begins_with("pressed") or state.begins_with("hover_pressed"):
			fill = bg.darkened(0.2)
		elif state.begins_with("disabled"):
			fill = c("disabled_bg")
		var box := _box(fill, border if not state.begins_with("disabled") else c("disabled_bg").darkened(0.3), 2, 5, 2)
		if state == "focus":
			box.draw_center = false
		b.add_theme_stylebox_override(state, box)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(color_name, fg)
	b.add_theme_color_override("font_disabled_color", c("disabled_text"))
	b.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.4))


static func _box(fill: Color, border: Color, border_width: int, margin_x: float, margin_y: float) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(border_width)
	s.anti_aliasing = false
	s.content_margin_left = margin_x
	s.content_margin_right = margin_x
	s.content_margin_top = margin_y
	s.content_margin_bottom = margin_y
	return s
