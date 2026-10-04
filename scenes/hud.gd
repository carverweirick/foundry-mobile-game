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
##
## Bottom-left: the Attention ("!") button (design doc 27.6). Shows how many
## things need the player (Attention.collect()); each tap emits
## attention_requested with the next one, and main.gd pans the camera there
## or opens the relevant menu. A short toast beside it says what it is.

## Emitted by an Attention tap - see Attention for the item's shape.
signal attention_requested(item: Dictionary)

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
## An iPhone 16 Pro's landscape insets in logical px at a 270px-tall view.
## Also the fallback for any wide handheld screen that reports none (see
## _safe_insets()). Desktop testing: launch with
## `-- --simulate-iphone-safe-area` to force them on.
const SIMULATE_SAFE_AREA_ARG := "--simulate-iphone-safe-area"
const SIMULATED_INSETS := {"left": 40.0, "top": 0.0, "right": 40.0, "bottom": 14.0}
## On a wide handheld screen the bar's ends stay this far from BOTH edges
## even when the camera is on the other side - the rounded corners still
## clip there, and the Settings gear sits at the bar's right end.
const CORNER_INSET: float = 22.0
## Desktop testing: fake a detected camera side, e.g. `-- --simulate-camera-left`.
const SIMULATE_CAMERA_LEFT_ARG := "--simulate-camera-left"
const SIMULATE_CAMERA_RIGHT_ARG := "--simulate-camera-right"
## Gravity is re-read this often; a side change needs two agreeing reads.
const CAMERA_SIDE_POLL_SECONDS: float = 0.5
const DEBT_COLOR := Color(0.85, 0.2, 0.2)
const ATTENTION_SIZE := Vector2(38.0, 36.0)
const ATTENTION_POLL_SECONDS: float = 0.25
const TOAST_SECONDS: float = 2.5
## Money popups (user request, 2026-10-03): every gain shows as a green
## "+Ng" under Gold that drifts down and fades.
const MONEY_POPUP_COLOR := Color(0.40, 0.90, 0.40)
const MONEY_POPUP_SECONDS: float = 1.4
const MONEY_POPUP_DRIFT: float = 14.0
const MONEY_POPUP_STACK: float = 11.0
## No popups for this long after start-up - loading a save and offline
## catch-up both move gold, and neither is "money just made".
const MONEY_POPUP_STARTUP_QUIET_SECONDS: float = 2.0
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
## Debug builds only - see bind_admin().
var _admin_button: Button = null
var _speed_badge: Label
var _rail_buttons: Array[Button] = []
## Every OverlayBase that opens into the panel slot (rail menus + Settings).
var _slot_overlays: Array[OverlayBase] = []
var _station_detail_menu: StationDetailMenu = null
## AUTO mode's current answer: CutoutSide.LEFT/RIGHT, or BOTH while unknown.
var _detected_camera_side: ThemeManager.CutoutSide = ThemeManager.CutoutSide.BOTH
var _pending_camera_side: ThemeManager.CutoutSide = ThemeManager.CutoutSide.BOTH
var _camera_poll_elapsed: float = 0.0
var _attention_button: Button
var _attention_count_label: Label
var _attention_toast: Label
var _attention_toast_tween: Tween
var _attention_items: Array[Dictionary] = []
var _attention_last_key: String = ""
var _attention_poll_elapsed: float = ATTENTION_POLL_SECONDS
var _last_currency: int = 0
var _money_popups: Array[Label] = []


func _ready() -> void:
	layer = 2
	_build_bar()
	_rail = VBoxContainer.new()
	_rail.add_theme_constant_override("separation", 2)
	add_child(_rail)
	_build_attention()
	ThemeManager.theme_changed.connect(func(_choice): _apply_theme())
	_apply_theme()
	get_viewport().size_changed.connect(_layout)
	ThemeManager.cutout_side_changed.connect(func(_side): _layout())
	_last_currency = GameData.currency
	GameData.currency_changed.connect(_on_currency_changed)


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
	if settings_overlay is SettingsOverlay:
		settings_overlay.hud = self
	settings_overlay.rail_button = _settings_button
	_slot_overlays.append(settings_overlay)
	_station_detail_menu = station_detail_menu
	_apply_theme()
	_layout()
	_log_safe_area_diagnostics()


func _process(delta: float) -> void:
	_camera_poll_elapsed += delta
	if _camera_poll_elapsed >= CAMERA_SIDE_POLL_SECONDS:
		_camera_poll_elapsed = 0.0
		_poll_camera_side()
	_attention_poll_elapsed += delta
	if _attention_poll_elapsed >= ATTENTION_POLL_SECONDS:
		_attention_poll_elapsed = 0.0
		_refresh_attention()
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
	_speed_badge.visible = GameData.debug_sim_speed != 1.0
	if _speed_badge.visible:
		_speed_badge.text = "PAUSED" if GameData.debug_sim_speed == 0.0 else "%dx" % int(GameData.debug_sim_speed)
	# The Station Detail Menu's two panels need ~464px, more than the slot
	# left of the rail on any phone shape, and it's modal anyway (a tap
	# outside closes it) - so the rail steps aside while it's open rather
	# than drawing half-covered underneath it.
	if _station_detail_menu != null:
		_rail.visible = not _station_detail_menu.panel.visible
	# A floor tool, not a menu one - and the bottom-left corner is under the
	# panel slot on narrower screens - so it steps aside while a menu is open.
	_attention_button.visible = not _any_menu_open()
	if not _attention_button.visible:
		_attention_toast.visible = false


func _on_currency_changed(new_amount: int) -> void:
	var gained := new_amount - _last_currency
	_last_currency = new_amount
	if gained <= 0 or GameData.is_catching_up:
		return
	if Time.get_ticks_msec() / 1000.0 < MONEY_POPUP_STARTUP_QUIET_SECONDS:
		return
	_show_money_popup(gained)


## A green "+Ng" just under the Gold readout that drifts down and fades;
## several quick gains stack downward instead of overlapping.
func _show_money_popup(amount: int) -> void:
	var popup := Label.new()
	popup.text = "+%dg" % amount
	popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	popup.add_theme_color_override("font_color", MONEY_POPUP_COLOR)
	popup.add_theme_color_override("font_outline_color", Color(0.05, 0.08, 0.04))
	popup.add_theme_constant_override("outline_size", 3)
	ThemeManager.apply_theme_to(popup)
	add_child(popup)
	var gold_rect := _gold_label.get_global_rect()
	popup.position = Vector2(gold_rect.position.x, _bar.position.y + _bar.size.y + 1.0 + MONEY_POPUP_STACK * _money_popups.size())
	_money_popups.append(popup)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(popup, "position:y", popup.position.y + MONEY_POPUP_DRIFT, MONEY_POPUP_SECONDS) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(popup, "modulate:a", 0.0, MONEY_POPUP_SECONDS * 0.6).set_delay(MONEY_POPUP_SECONDS * 0.4)
	tween.chain().tween_callback(func():
		_money_popups.erase(popup)
		popup.queue_free())


func _any_menu_open() -> bool:
	if _station_detail_menu != null and _station_detail_menu.panel.visible:
		return true
	for overlay in _slot_overlays:
		if overlay.panel.visible:
			return true
	return false


func _build_attention() -> void:
	_attention_button = _make_rail_tile("0", "attention")
	_attention_button.tooltip_text = UiText.tip("Jump to the next thing that needs you")
	_attention_button.focus_mode = Control.FOCUS_NONE
	_attention_button.size = ATTENTION_SIZE
	_attention_count_label = _attention_button.get_child(0).get_child(1)
	_attention_button.pressed.connect(_on_attention_pressed)
	add_child(_attention_button)
	# Same white-on-black-outline treatment as the floor's station labels, so
	# it reads over any floor tile without a panel behind it.
	_attention_toast = Label.new()
	_attention_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_attention_toast.add_theme_color_override("font_color", Color(0.98, 0.95, 0.88))
	_attention_toast.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.03))
	_attention_toast.add_theme_constant_override("outline_size", 3)
	_attention_toast.visible = false
	add_child(_attention_toast)


func _refresh_attention() -> void:
	_attention_items = Attention.collect()
	_attention_count_label.text = str(_attention_items.size())
	_attention_button.disabled = _attention_items.is_empty()


## Steps to the item after the last one visited, so repeated taps tour every
## need; once that one is resolved it drops out and the tour restarts at the
## most urgent.
func _on_attention_pressed() -> void:
	_refresh_attention()
	if _attention_items.is_empty():
		return
	var index := 0
	for i in _attention_items.size():
		if _attention_items[i].key == _attention_last_key:
			index = (i + 1) % _attention_items.size()
			break
	var item: Dictionary = _attention_items[index]
	_attention_last_key = item.key
	_show_attention_toast("%s  (%d/%d)" % [item.label, index + 1, _attention_items.size()])
	attention_requested.emit(item)


func _show_attention_toast(text: String) -> void:
	_attention_toast.text = text
	_attention_toast.visible = true
	_attention_toast.modulate.a = 1.0
	if _attention_toast_tween != null:
		_attention_toast_tween.kill()
	_attention_toast_tween = create_tween()
	_attention_toast_tween.tween_interval(TOAST_SECONDS)
	_attention_toast_tween.tween_property(_attention_toast, "modulate:a", 0.0, 0.4)
	_attention_toast_tween.tween_callback(func(): _attention_toast.visible = false)


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
	# Shown only while the admin game speed isn't 1x, so a sped-up or paused
	# test session is never mistaken for normal pacing.
	_speed_badge = Label.new()
	_speed_badge.add_theme_color_override("font_color", Color(0.95, 0.72, 0.2))
	_speed_badge.visible = false
	row.add_child(_speed_badge)
	if OS.is_debug_build():
		_admin_button = Button.new()
		_admin_button.icon = UiIcons.get_icon("admin")
		_admin_button.toggle_mode = true
		_admin_button.focus_mode = Control.FOCUS_NONE
		_admin_button.tooltip_text = "Admin / test controls"
		row.add_child(_admin_button)
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
	ThemeManager.apply_theme_to(_attention_button)
	ThemeManager.apply_theme_to(_attention_toast)
	var theme: Theme = ThemeManager.get_current_theme_resource()
	var bar_style: StyleBox = theme.get_stylebox("panel", "Panel").duplicate()
	if bar_style is StyleBoxFlat:
		bar_style.set_border_width_all(2)
	bar_style.content_margin_left = 6.0
	bar_style.content_margin_right = 3.0
	bar_style.content_margin_top = 1.0
	bar_style.content_margin_bottom = 1.0
	_bar.add_theme_stylebox_override("panel", bar_style)
	var styled: Array[Button] = _rail_buttons.duplicate()
	styled.append_array([_settings_button, _attention_button])
	if _admin_button != null:
		styled.append(_admin_button)
	for button: Button in styled:
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
	var camera_side := _camera_side()
	if camera_side == ThemeManager.CutoutSide.LEFT:
		insets.right = 0.0
	elif camera_side == ThemeManager.CutoutSide.RIGHT:
		insets.left = 0.0
	var left: float = insets.left
	var right: float = view.x - insets.right
	var bottom: float = view.y - insets.bottom - EDGE_GAP

	var corner: float = CORNER_INSET if _is_wide_handheld(view) else 0.0
	var bar_left: float = maxf(left, corner)
	var bar_right: float = minf(right, view.x - corner)
	_bar.position = Vector2(bar_left, insets.top)
	_bar.size = Vector2(bar_right - bar_left, BAR_HEIGHT)
	var bar_bottom: float = _bar.position.y + maxf(BAR_HEIGHT, _bar.get_combined_minimum_size().y)

	var top: float = bar_bottom + EDGE_GAP
	_rail.position = Vector2(right - RAIL_WIDTH, top)
	_rail.size = Vector2(RAIL_WIDTH, bottom - top)

	var slot_right: float = _rail.position.x - EDGE_GAP
	var slot_left: float = maxf(left + EDGE_GAP, slot_right - PANEL_MAX_WIDTH)
	var slot := Rect2(slot_left, top, slot_right - slot_left, bottom - top)
	for overlay in _slot_overlays:
		overlay.set_panel_rect(slot)

	var attention_x: float = maxf(left, corner) + EDGE_GAP
	_attention_button.position = Vector2(attention_x, bottom - ATTENTION_SIZE.y)
	_attention_button.size = ATTENTION_SIZE
	_attention_toast.position = Vector2(
		attention_x + ATTENTION_SIZE.x + EDGE_GAP,
		bottom - (ATTENTION_SIZE.y + _attention_toast.get_combined_minimum_size().y) * 0.5)

	if _station_detail_menu != null:
		var sdm_panel: Control = _station_detail_menu.panel
		var rack: Control = _station_detail_menu.rack_panel
		sdm_panel.position = Vector2(left + EDGE_GAP, top)
		sdm_panel.size.y = bottom - top
		rack.position = Vector2(sdm_panel.position.x + sdm_panel.size.x + EDGE_GAP, top)
		rack.size.y = bottom - top


## Device safe-area insets converted into logical viewport px.
##
## Two layers, because the first one returned nothing on the user's iPhone
## 16 Pro under Xogot (the HUD ran edge to edge and the Dynamic Island
## covered the rail): the OS-reported safe area, floored at SIMULATED_INSETS
## on any handheld screen 2:1 or wider - every phone that shape has rounded
## corners and a camera cutout.
## Returned symmetric left/right (iOS itself reports it that way in
## landscape); _layout() then drops the side without the camera, per
## _camera_side().
func _safe_insets(view: Vector2) -> Dictionary:
	if SIMULATE_SAFE_AREA_ARG in OS.get_cmdline_user_args():
		return SIMULATED_INSETS.duplicate()
	var none := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	var is_phone_os := _is_phone_os()
	if not _is_handheld():
		return none
	var reported := none
	var window := Vector2(DisplayServer.window_get_size())
	# Desktop get_display_safe_area() describes the monitor, not this window,
	# so the reported area is only read on a phone OS.
	if is_phone_os and window.x > 0.0 and window.y > 0.0:
		var safe := Rect2(DisplayServer.get_display_safe_area())
		var k: Vector2 = view / window
		var side: float = maxf(safe.position.x, window.x - safe.end.x) * k.x
		reported = {
			"left": maxf(0.0, side),
			"top": maxf(0.0, safe.position.y * k.y),
			"right": maxf(0.0, side),
			"bottom": maxf(0.0, (window.y - safe.end.y) * k.y),
		}
	if not _is_wide_handheld(view):
		return reported
	# Wide handheld: never less than the fallback on the sides/bottom, in case
	# the platform under-reports (or reports a portrait-shaped area). Top stays
	# 0 - the game is landscape-locked and a landscape phone has no top inset.
	return {
		"left": maxf(reported.left, SIMULATED_INSETS.left),
		"top": 0.0,
		"right": maxf(reported.right, SIMULATED_INSETS.right),
		"bottom": maxf(reported.bottom, SIMULATED_INSETS.bottom),
	}


func _is_phone_os() -> bool:
	return OS.has_feature("mobile") or OS.get_name() in ["iOS", "Android"]


func _is_handheld() -> bool:
	return _is_phone_os() or DisplayServer.is_touchscreen_available() \
		or SIMULATE_SAFE_AREA_ARG in OS.get_cmdline_user_args()


func _is_wide_handheld(view: Vector2) -> bool:
	return _is_handheld() and view.y > 0.0 and view.x / view.y >= 2.0


## Which side gets the cutout inset: the player's Settings choice, or in AUTO
## the gravity-detected side (BOTH until a confident reading arrives).
func _camera_side() -> ThemeManager.CutoutSide:
	var args := OS.get_cmdline_user_args()
	if SIMULATE_CAMERA_LEFT_ARG in args:
		return ThemeManager.CutoutSide.LEFT
	if SIMULATE_CAMERA_RIGHT_ARG in args:
		return ThemeManager.CutoutSide.RIGHT
	if ThemeManager.cutout_side != ThemeManager.CutoutSide.AUTO:
		return ThemeManager.cutout_side
	return _detected_camera_side


## Godot gives no way to read which landscape direction the interface is in
## (screen_get_orientation() returns the configured orientation, not the
## current one, and iOS reports a symmetric safe area), so AUTO infers it
## from the gravity sensor. In raw device axes, landscape with the top of
## the phone (the camera end) to the left puts gravity along -x, to the right
## along +x. If the platform instead reports gravity already rotated into
## screen space, x stays near 0 when held upright and this never commits -
## BOTH stays the answer, and the Settings override is the way out. The sign
## convention is unverified on real hardware: the [Hud] log line below and
## the Settings override exist for exactly that.
func _detect_camera_side() -> ThemeManager.CutoutSide:
	var gravity: Vector3 = Input.get_gravity()
	if gravity.length() < 4.0 or absf(gravity.x) < absf(gravity.y) * 1.5:
		return _detected_camera_side
	return ThemeManager.CutoutSide.LEFT if gravity.x < 0.0 else ThemeManager.CutoutSide.RIGHT


func _poll_camera_side() -> void:
	if ThemeManager.cutout_side != ThemeManager.CutoutSide.AUTO or not _is_phone_os():
		return
	var reading := _detect_camera_side()
	if reading == _detected_camera_side:
		_pending_camera_side = reading
		return
	if reading != _pending_camera_side:
		_pending_camera_side = reading
		return
	_detected_camera_side = reading
	print("[Hud] gravity=%s -> camera side %s" % [Input.get_gravity(), ThemeManager.CUTOUT_SIDE_DISPLAY_NAMES[reading]])
	_layout()


## Wires the debug-only wrench to the Admin overlay, which opens into the same
## panel slot as every rail menu. A release build has no wrench, so the
## overlay is simply never reachable there.
func bind_admin(admin_overlay: OverlayBase) -> void:
	if _admin_button == null:
		return
	_admin_button.pressed.connect(admin_overlay.toggle)
	admin_overlay.rail_button = _admin_button
	_slot_overlays.append(admin_overlay)
	_apply_theme()
	_layout()


## An overlay with no button of its own (e.g. the NC shelf menu, opened from
## the floor or the Attention button) that still opens into the shared panel
## slot beside the rail.
func add_slot_overlay(overlay: OverlayBase) -> void:
	_slot_overlays.append(overlay)
	_layout()


## Shown by the Settings overlay next to its cutout option.
func detected_camera_side_name() -> String:
	return ThemeManager.CUTOUT_SIDE_DISPLAY_NAMES[_detected_camera_side]


## One startup line so a device run shows what the platform actually
## reported - the safe-area path above has already been wrong once on real
## hardware.
func _log_safe_area_diagnostics() -> void:
	print("[Hud] os=%s mobile=%s touch=%s gravity=%s window=%s screen=%s safe_area=%s view=%s -> insets=%s" % [
		OS.get_name(), OS.has_feature("mobile"), DisplayServer.is_touchscreen_available(), Input.get_gravity(),
		DisplayServer.window_get_size(), DisplayServer.screen_get_size(),
		DisplayServer.get_display_safe_area(), get_viewport().get_visible_rect().size,
		_safe_insets(get_viewport().get_visible_rect().size),
	])
