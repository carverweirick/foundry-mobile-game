extends OverlayBase
class_name SettingsOverlay

## First real occupant of design doc Section 19's planned Settings Menu -
## scoped down to just the one option asked for this session (an in-game way
## to switch the UI's visual theme, rather than the dark industrial reskin
## from the gdt-layout-experiment merge being the only look) rather than the
## full audio/text-size/haptics/etc. list Section 19 describes. Establishes
## the entry point/pattern any of those later settings would slot into.

@onready var theme_status_label: Label = %ThemeStatusLabel
@onready var switch_theme_button: Button = %SwitchThemeButton

## Set by Hud.bind(), for showing the auto-detected camera side.
var hud: Hud = null
var _cutout_button: Button
var _art_button: Button


func _on_ready() -> void:
	switch_theme_button.pressed.connect(_on_switch_theme_pressed)
	ThemeManager.theme_changed.connect(func(_choice): _refresh())
	# Which edge the phone's camera cutout is on, so the Hud only insets that
	# side (design doc Section 27). Auto relies on the gravity sensor, which
	# may not report usefully on every device - this is the manual way out.
	var content: VBoxContainer = panel.get_node("Content")
	content.add_child(HSeparator.new())
	var cutout_header := Label.new()
	cutout_header.text = "Camera cutout side (keeps the menus clear of it)"
	cutout_header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(cutout_header)
	_cutout_button = Button.new()
	_cutout_button.pressed.connect(_on_cutout_pressed)
	content.add_child(_cutout_button)
	ThemeManager.cutout_side_changed.connect(func(_side): _refresh())
	# Two complete station art sets (see StationArt): hand-built 8-bit
	# sprites, or the AI-painted set.
	content.add_child(HSeparator.new())
	var art_header := Label.new()
	art_header.text = "Station art"
	content.add_child(art_header)
	_art_button = Button.new()
	_art_button.pressed.connect(_on_art_pressed)
	content.add_child(_art_button)
	ThemeManager.station_art_changed.connect(func(_style): _refresh())


func _on_open() -> void:
	_refresh()


func _refresh() -> void:
	var current: ThemeManager.ThemeChoice = ThemeManager.current_theme
	theme_status_label.text = "Current theme: %s" % ThemeManager.THEME_DISPLAY_NAMES[current]
	switch_theme_button.text = "Switch to %s" % ThemeManager.THEME_DISPLAY_NAMES[_other_theme(current)]
	var side: ThemeManager.CutoutSide = ThemeManager.cutout_side
	var side_text: String = ThemeManager.CUTOUT_SIDE_DISPLAY_NAMES[side]
	if side == ThemeManager.CutoutSide.AUTO and hud != null:
		side_text += " (detected: %s)" % hud.detected_camera_side_name()
	_cutout_button.text = "Cutout: %s - tap to change" % side_text
	_art_button.text = "Station art: %s - tap to change" % ThemeManager.STATION_ART_DISPLAY_NAMES[ThemeManager.station_art]


func _on_art_pressed() -> void:
	var next: int = (ThemeManager.station_art + 1) % ThemeManager.STATION_ART_DISPLAY_NAMES.size()
	ThemeManager.set_station_art(next as ThemeManager.StationArtStyle)
	_refresh.call_deferred()


func _on_cutout_pressed() -> void:
	var next: int = (ThemeManager.cutout_side + 1) % ThemeManager.CUTOUT_SIDE_DISPLAY_NAMES.size()
	ThemeManager.set_cutout_side(next as ThemeManager.CutoutSide)
	_refresh.call_deferred()


func _on_switch_theme_pressed() -> void:
	ThemeManager.set_theme(_other_theme(ThemeManager.current_theme))
	_refresh.call_deferred()


func _other_theme(choice: ThemeManager.ThemeChoice) -> ThemeManager.ThemeChoice:
	if choice == ThemeManager.ThemeChoice.DARK:
		return ThemeManager.ThemeChoice.PARCHMENT
	return ThemeManager.ThemeChoice.DARK
