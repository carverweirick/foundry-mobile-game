extends CanvasLayer
class_name Hud

## The always-visible HUD (design doc Section 27.2): a resource bar along the
## top (from the "Bottom Command Belt" mockup) and a vertical rail of
## icon+label menu buttons down the right edge (from the "Edge Tabs and
## Floating Panel" mockup). Every menu overlay opens into one shared panel
## slot beside the rail, so the rail stays tappable while a menu is open.
##
## Everything is positioned in code from the live viewport size and the
## device safe area, never from fixed 480x270 coordinates - the viewport
## widens on phones wider than 16:9 (stretch aspect "expand"), and on an
## iPhone in landscape the rounded corners and Dynamic Island clip the outer
## ~40 logical px each side. The old HUD's fixed offsets are exactly what
## left the buttons floating mid-screen and the currency label cut off.
##
## Layering: this is layer 2 - above every OverlayBase (layer 1, including
## its full-screen Backdrop), so rail taps reach the rail instead of closing
## the open menu; below StationDetailMenu (layer 3), which is modal over
## everything since it's opened from a floor tap rather than the rail (the
## rail hides while it's open, see _process()).

const BAR_HEIGHT: float = 20.0
const RAIL_WIDTH: float = 62.0
## Icon (16) + one m5x7 line (13) + a little air. Tiles stretch to share
## the rail's height; this is the floor they won't squeeze below.
const RAIL_TILE_MIN_HEIGHT: float = 32.0
const EDGE_GAP: float = 4.0
## A menu panel never gets wider than this, so on a wide enough screen some
## floor stays visible beside it. Current menu contents need most of it -
## narrowing further waits on the menu redesign (Section 27.3).
const PANEL_MAX_WIDTH: float = 400.0
## Desktop testing aid: launch with `-- --simulate-iphone-safe-area` to get
## an iPhone 16 Pro's landscape insets (in logical px at a 270px-tall view).
const SIMULATE_SAFE_AREA_ARG := "--simulate-iphone-safe-area"
const SIMULATED_INSETS := {"left": 40.0, "top": 0.0, "right": 40.0, "bottom": 14.0}
const DEBT_COLOR := Color(0.85, 0.2, 0.2)
const BUTTON_STATES: Array[String] = [
	"normal", "normal_mirrored", "hover", "hover_mirrored", "pressed",
	"pressed_mirrored", "hover_pressed", "hover_pressed_mirrored", "disabled",
	"disabled_mirrored", "focus",
]

var _bar: PanelContainer
var _rail: VBoxContainer
var _gold_label: Label
var _gems_label: Label
var _reputation_label: Label
var _level_label: Label
var _settings_button: Button
var _rail_buttons: Array[Button] = []
## Every OverlayBase that opens into the panel slot (rail menus + Settings).
var _slot_overlays: Array[OverlayBase] = []
var _station_detail_menu: StationDetailMenu = null


func _ready() -> void:
	layer = 2
	_build_bar()
	_rail = VBoxContainer.new()
	_rail.add_theme_constant_override("separation", 2)
	add_child(_rail)
	ThemeManager.theme_changed.connect(func(_choice): _apply_theme())
	_apply_theme()
	get_viewport().size_changed.connect(_layout)


## Called once by main.gd after every overlay exists. rail_entries is an
## Array of [OverlayBase, label text, UiIcons icon name], top to bottom.
func bind(rail_entries: Array, settings_overlay: OverlayBase, station_detail_menu: StationDetailMenu) -> void:
	for entry in rail_entries:
		var overlay: OverlayBase = entry[0]
		var button := _make_rail_tile(entry[1], entry[2])
		button.toggle_mode = true
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.focus_mode = Control.FOCUS_NONE
		button.pressed.connect(overlay.toggle)
		overlay.rail_button = button
		_rail.add_child(button)
		_rail_buttons.append(button)
		_slot_overlays.append(overlay)
	_settings_button.pressed.connect(settings_overlay.toggle)
	settings_overlay.rail_button = _settings_button
	_slot_overlays.append(settings_overlay)
	_station_detail_menu = station_detail_menu
	_apply_theme()
	_layout()


func _process(_delta: float) -> void:
	# Polled rather than signal-driven: a save load can replace every one of
	# these values without emitting, and set_text() is a no-op when unchanged.
	_gold_label.text = "Gold: %dg" % GameData.currency
	if GameData.is_in_wage_debt():
		_gold_label.add_theme_color_override("font_color", DEBT_COLOR)
	else:
		_gold_label.remove_theme_color_override("font_color")
	_gems_label.text = "Gems: %d" % GameData.gems
	_reputation_label.text = "Reputation: %d" % GameData.reputation
	_level_label.text = "Factory Lv: %d" % GameData.factory_level
	# The Station Detail Menu's two panels need ~464px, more than the slot
	# left of the rail on any phone shape, and it's modal anyway (a tap
	# outside closes it) - so the rail steps aside while it's open rather
	# than drawing half-covered underneath it.
	if _station_detail_menu != null:
		_rail.visible = not _station_detail_menu.panel.visible


func _build_bar() -> void:
	_bar = PanelContainer.new()
	add_child(_bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	_bar.add_child(row)
	_gold_label = _add_stat(row, "gold")
	_gems_label = _add_stat(row, "gems")
	_reputation_label = _add_stat(row, "reputation")
	_level_label = _add_stat(row, "factory")
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(spacer)
	_settings_button = Button.new()
	_settings_button.icon = UiIcons.get_icon("settings")
	_settings_button.toggle_mode = true
	_settings_button.focus_mode = Control.FOCUS_NONE
	_settings_button.tooltip_text = "Settings"
	row.add_child(_settings_button)


## A rail button drawn as icon-over-label. Not Button.icon with
## vertical_icon_alignment = TOP: in that mode Godot reserves an extra text
## line, so each button came out 45px tall and six of them overflowed a
## 270px-tall screen. A plain Button with its own centered VBox child sizes
## to exactly icon + label + margins. The tooltip keeps the name available
## when a narrow screen squeezes the tile.
func _make_rail_tile(text: String, icon_name: String) -> Button:
	var button := Button.new()
	button.tooltip_text = text
	button.custom_minimum_size = Vector2(0.0, RAIL_TILE_MIN_HEIGHT)
	var stack := VBoxContainer.new()
	stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 0)
	stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(stack)
	var icon := TextureRect.new()
	icon.texture = UiIcons.get_icon(icon_name)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(icon)
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack.add_child(label)
	return button


## Icon + short single-line Label. No autowrap on purpose (CLAUDE.md UI rule
## 1): inside an HBoxContainer an autowrapping Label collapses to a sliver.
func _add_stat(row: HBoxContainer, icon_name: String) -> Label:
	var stat := HBoxContainer.new()
	stat.add_theme_constant_override("separation", 3)
	stat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(stat)
	var icon := TextureRect.new()
	icon.texture = UiIcons.get_icon(icon_name)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stat.add_child(icon)
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stat.add_child(label)
	return label


## The bar and rail buttons reuse the current Theme's own StyleBoxes, just
## with thinner borders/margins - the full-size ones (4px panel border, 10px
## button margins) don't fit a 20px bar or six stacked rail buttons.
func _apply_theme() -> void:
	ThemeManager.apply_theme_to(_bar)
	ThemeManager.apply_theme_to(_rail)
	var theme: Theme = ThemeManager.get_current_theme_resource()
	var bar_style: StyleBox = theme.get_stylebox("panel", "Panel").duplicate()
	if bar_style is StyleBoxFlat:
		bar_style.set_border_width_all(2)
	bar_style.content_margin_left = 6.0
	bar_style.content_margin_right = 3.0
	bar_style.content_margin_top = 1.0
	bar_style.content_margin_bottom = 1.0
	_bar.add_theme_stylebox_override("panel", bar_style)
	for button: Button in _rail_buttons + [_settings_button]:
		# EVERY state, including ones this Theme doesn't define: a Button's
		# minimum size is its largest stylebox across all states, and an
		# undefined one (hover_pressed, the *_mirrored RTL variants) falls back
		# to Godot's roomier default - which alone made each rail button 45px
		# tall and pushed the sixth one off the bottom of the screen.
		for state in BUTTON_STATES:
			var source: String = state.trim_suffix("_mirrored")
			if source == "hover_pressed" and not theme.has_stylebox(source, "Button"):
				source = "pressed"
			if not theme.has_stylebox(source, "Button"):
				source = "normal"
			var style: StyleBox = theme.get_stylebox(source, "Button").duplicate()
			style.content_margin_left = 2.0
			style.content_margin_right = 2.0
			style.content_margin_top = 2.0
			style.content_margin_bottom = 1.0
			button.add_theme_stylebox_override(state, style)
		button.add_theme_constant_override("h_separation", 1)


func _layout() -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	var insets := _safe_insets(view)
	var left: float = insets.left
	var right: float = view.x - insets.right
	var bottom: float = view.y - insets.bottom - EDGE_GAP

	_bar.position = Vector2(left, insets.top)
	_bar.size = Vector2(right - left, BAR_HEIGHT)
	var bar_bottom: float = _bar.position.y + maxf(BAR_HEIGHT, _bar.get_combined_minimum_size().y)

	var top: float = bar_bottom + EDGE_GAP
	_rail.position = Vector2(right - RAIL_WIDTH, top)
	_rail.size = Vector2(RAIL_WIDTH, bottom - top)

	var slot_right: float = _rail.position.x - EDGE_GAP
	var slot_left: float = maxf(left + EDGE_GAP, slot_right - PANEL_MAX_WIDTH)
	var slot := Rect2(slot_left, top, slot_right - slot_left, bottom - top)
	for overlay in _slot_overlays:
		overlay.set_panel_rect(slot)

	if _station_detail_menu != null:
		var sdm_panel: Control = _station_detail_menu.panel
		var rack: Control = _station_detail_menu.rack_panel
		sdm_panel.position = Vector2(left + EDGE_GAP, top)
		sdm_panel.size.y = bottom - top
		rack.position = Vector2(sdm_panel.position.x + sdm_panel.size.x + EDGE_GAP, top)
		rack.size.y = bottom - top


## Device safe-area insets converted into logical viewport px. Only trusted
## on mobile - on desktop get_display_safe_area() describes the monitor, not
## this window.
func _safe_insets(view: Vector2) -> Dictionary:
	if SIMULATE_SAFE_AREA_ARG in OS.get_cmdline_user_args():
		return SIMULATED_INSETS
	var none := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	if not OS.has_feature("mobile"):
		return none
	var window := Vector2(DisplayServer.window_get_size())
	if window.x <= 0.0 or window.y <= 0.0:
		return none
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var k: Vector2 = view / window
	return {
		"left": maxf(0.0, safe.position.x * k.x),
		"top": maxf(0.0, safe.position.y * k.y),
		"right": maxf(0.0, (window.x - safe.end.x) * k.x),
		"bottom": maxf(0.0, (window.y - safe.end.y) * k.y),
	}
