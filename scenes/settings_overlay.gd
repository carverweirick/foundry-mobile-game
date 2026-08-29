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


func _on_ready() -> void:
	switch_theme_button.pressed.connect(_on_switch_theme_pressed)
	ThemeManager.theme_changed.connect(func(_choice): _refresh())


func _on_open() -> void:
	_refresh()


func _refresh() -> void:
	var current: ThemeManager.ThemeChoice = ThemeManager.current_theme
	theme_status_label.text = "Current theme: %s" % ThemeManager.THEME_DISPLAY_NAMES[current]
	switch_theme_button.text = "Switch to %s" % ThemeManager.THEME_DISPLAY_NAMES[_other_theme(current)]


func _on_switch_theme_pressed() -> void:
	ThemeManager.set_theme(_other_theme(ThemeManager.current_theme))
	_refresh.call_deferred()


func _other_theme(choice: ThemeManager.ThemeChoice) -> ThemeManager.ThemeChoice:
	if choice == ThemeManager.ThemeChoice.DARK:
		return ThemeManager.ThemeChoice.PARCHMENT
	return ThemeManager.ThemeChoice.DARK
